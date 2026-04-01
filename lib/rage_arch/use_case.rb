# frozen_string_literal: true

require "active_support/inflector"

module RageArch
  module UseCase
    # Tracks successful use case executions for cascade undo on failure.
    class ExecutionTracker
      def initialize
        @recorded = []
      end

      def record(use_case_instance, result)
        @recorded << { use_case: use_case_instance, result: result }
      end

      def undo_all
        @recorded.reverse_each do |entry|
          uc = entry[:use_case]
          uc.undo(entry[:result].value) if uc.respond_to?(:undo)
        end
      end

      def clear
        @recorded.clear
      end
    end

    # Wraps a use case runner to track successful calls for cascade undo.
    class UseCaseProxy
      def initialize(symbol, tracker:)
        @symbol = symbol
        @tracker = tracker
      end

      def call(params = {})
        use_case = Base.build(@symbol)
        result = use_case.call(params)
        @tracker.record(use_case, result) if result.success?
        result
      end
    end

    # Runs another use case by symbol (legacy, used when no tracker is active).
    class Runner
      def initialize(symbol)
        @symbol = symbol
      end

      def call(*args, **kwargs)
        Base.build(@symbol).call(*args, **kwargs)
      end
    end

    # Base for use cases: register by symbol, deps injected via constructor.
    #
    # Usage:
    #   class CreateOrder < RageArch::UseCase::Base
    #     deps :order_store, :notifications
    #
    #     def call(params = {})
    #       order = order_store.build(params)
    #       success(order)
    #     end
    #   end
    #
    # Building: RageArch::UseCase::Base.build(:create_order) resolves deps from
    # RageArch::Container and returns an instance of the use case.
    class Base
      module Instrumentation
        def call(params = {})
          sym = self.class.use_case_symbol

          # Set up execution tracker for cascade undo via use_cases
          @_execution_tracker = ExecutionTracker.new

          if defined?(ActiveSupport::Notifications)
            ActiveSupport::Notifications.instrument("rage_arch.use_case.run", symbol: sym, params: params) do |payload|
              result = super(params)
              payload[:success] = result.success?
              payload[:errors] = result.errors unless result.success?
              payload[:result] = result
              handle_undo_and_publish(sym, params, result)
              result
            end
          else
            result = super(params)
            handle_undo_and_publish(sym, params, result)
            result
          end
        end

        private

        def handle_undo_and_publish(use_case_symbol, params, result)
          if result.failure?
            # Cascade undo: reverse-order undo of tracked child use cases
            @_execution_tracker&.undo_all
            # Self undo
            undo(result.value) if respond_to?(:undo)
          end
          auto_publish_if_enabled(use_case_symbol, params, result)
        end

        def auto_publish_if_enabled(use_case_symbol, params, result)
          return unless auto_publish_enabled?
          return unless self.class.container.registered?(:event_publisher)
          publisher = self.class.container.resolve(:event_publisher)
          publisher.publish(
            use_case_symbol,
            use_case: use_case_symbol,
            params: params,
            success: result.success?,
            value: result.value,
            errors: result.errors
          )
        end

        def auto_publish_enabled?
          return false if self.class.skip_auto_publish?
          return true unless defined?(Rails) && Rails.application.config.respond_to?(:rage_arch) && Rails.application.config.rage_arch
          Rails.application.config.rage_arch.auto_publish_events != false
        end
      end

      include Instrumentation

      class << self
        def inherited(subclass)
          super
          subclass.prepend(Instrumentation)
        end

        def use_case_symbol(sym = nil)
          if sym
            @use_case_symbol = sym
            Base.registry[sym] = self
            sym
          else
            @use_case_symbol ||= infer_use_case_symbol
          end
        end

        def deps(*symbols)
          @declared_deps ||= []
          @declared_deps.concat(symbols)
          symbols.each do |sym|
            define_method(sym) { injected_deps.fetch(sym) }
          end
          private(*symbols) if symbols.any?
          symbols
        end

        # Declare other use cases this one can call. In call(), use e.g. posts_create.call(params)
        # to run that use case and get its Result. Tracked for cascade undo on failure.
        def use_cases(*symbols)
          @declared_use_cases ||= []
          @declared_use_cases.concat(symbols)
          symbols.each do |sym|
            define_method(sym) do
              if @_execution_tracker
                UseCaseProxy.new(sym, tracker: @_execution_tracker)
              else
                Runner.new(sym)
              end
            end
          end
          private(*symbols) if symbols.any?
          symbols
        end

        def declared_use_cases
          @declared_use_cases || []
        end

        # Subscribe this use case to domain events. When the event is published, this use case's call(payload) runs.
        # You can subscribe to multiple events: subscribe :post_created, :post_updated
        # Special: subscribe :all to run on every published event (payload will include :event).
        # By default subscribers run asynchronously via ActiveJob. Use async: false for synchronous execution.
        def subscribe(*event_names, async: true)
          @subscribed_events ||= []
          event_names.each do |ev|
            @subscribed_events << { event: ev.to_sym, async: async }
          end
          event_names
        end

        def subscribed_events
          (@subscribed_events || []).map { |e| e[:event] }
        end

        def subscription_entries
          @subscribed_events || []
        end

        # Opt-out of auto-publish when this use case finishes (e.g. for the logger use case itself).
        def skip_auto_publish
          @skip_auto_publish = true
        end

        def skip_auto_publish?
          @skip_auto_publish == true
        end

        # Call once after loading use cases and before registering the publisher. Registers each use case's
        # subscribed_events with the publisher so they run when those events are published.
        def wire_subscriptions_to(publisher)
          registry.each do |symbol, klass|
            next unless klass.respond_to?(:subscription_entries)
            klass.subscription_entries.each do |entry|
              if entry[:async] && async_subscribers_enabled?
                publisher.subscribe(entry[:event], async_runner(symbol))
              else
                publisher.subscribe(entry[:event], symbol)
              end
            end
          end
          nil
        end

        def declared_deps
          @declared_deps || []
        end

        def registry
          @registry ||= {}
        end

        def resolve(symbol)
          Base.registry[symbol] or raise KeyError, "Use case not registered: #{symbol.inspect}"
        end

        def build(symbol)
          klass = Base.resolve(symbol)
          deps_hash = klass.declared_deps.uniq.to_h do |s|
            [s, container.resolve(s)]
          end
          klass.new(**deps_hash)
        end

        def container
          RageArch::Container
        end

        private

        def infer_use_case_symbol
          return nil unless name
          sym = ::ActiveSupport::Inflector.underscore(name).gsub("/", "_").to_sym
          Base.registry[sym] = self
          sym
        end

        def async_subscribers_enabled?
          return false unless defined?(ActiveJob)
          return true unless defined?(Rails) && Rails.application&.config&.respond_to?(:rage_arch) && Rails.application.config.rage_arch
          Rails.application.config.rage_arch.async_subscribers != false
        end

        def async_runner(symbol)
          ->(payload) { RageArch::SubscriberJob.perform_later(symbol.to_s, payload) }
        end
      end

      def initialize(**injected_deps)
        @injected_deps = injected_deps
      end

      def call(_params = {})
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      def success(value = nil)
        RageArch::Result.success(value)
      end

      def failure(errors)
        RageArch::Result.failure(errors)
      end

      private

      def injected_deps
        @injected_deps ||= {}
      end

      def dep(symbol, default: nil)
        return injected_deps[symbol] if injected_deps.key?(symbol)

        if container.registered?(symbol)
          container.resolve(symbol)
        elsif default
          impl = resolve_default(default)
          impl.is_a?(Class) ? impl.new : impl
        else
          raise KeyError, "Dep not registered and no default: #{symbol.inspect}"
        end
      end

      def resolve_default(default)
        if default.is_a?(Class) && active_record_model?(default)
          RageArch::Deps::ActiveRecord.for(default)
        else
          default
        end
      end

      def active_record_model?(klass)
        defined?(ActiveRecord::Base) && klass < ActiveRecord::Base
      rescue
        false
      end

      def container
        self.class.container
      end
    end
  end
end
