# frozen_string_literal: true

module RageArch
  module UseCase
    # Runs another use case by symbol. Used when a use case declares use_cases :other_symbol.
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
    #     use_case_symbol :create_order
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
          if defined?(ActiveSupport::Notifications)
            ActiveSupport::Notifications.instrument("rage_arch.use_case.run", symbol: sym, params: params) do |payload|
              result = super(params)
              payload[:success] = result.success?
              payload[:errors] = result.errors unless result.success?
              payload[:result] = result
              auto_publish_if_enabled(sym, params, result)
              result
            end
          else
            result = super(params)
            auto_publish_if_enabled(sym, params, result)
            result
          end
        end

        private

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
            @use_case_symbol
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
        # to run that use case and get its Result. Same layer can reference by symbol.
        def use_cases(*symbols)
          @declared_use_cases ||= []
          @declared_use_cases.concat(symbols)
          symbols.each do |sym|
            define_method(sym) { Runner.new(sym) }
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
        def subscribe(*event_names)
          @subscribed_events ||= []
          @subscribed_events.concat(event_names.map(&:to_sym))
          event_names
        end

        def subscribed_events
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
            next unless klass.respond_to?(:subscribed_events)
            klass.subscribed_events.each do |event_name|
              publisher.subscribe(event_name, symbol)
            end
          end
          nil
        end

        # Dep that uses Active Record for the model when not registered in the container.
        # Example: ar_dep :user_store, User  (instead of default: RageArch::Deps::ActiveRecord.for(User))
        def ar_dep(symbol, model_class)
          @ar_deps ||= {}
          @ar_deps[symbol] = model_class
          deps(symbol)
        end

        def ar_deps
          @ar_deps || {}
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
            if klass.ar_deps.key?(s)
              impl = container.registered?(s) ? container.resolve(s) : Deps::ActiveRecord.for(klass.ar_deps[s])
              [s, impl]
            else
              [s, container.resolve(s)]
            end
          end
          klass.new(**deps_hash)
        end

        def container
          RageArch::Container
        end
      end

      def initialize(**injected_deps)
        @injected_deps = injected_deps
      end

      def call(_params = {})
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      # From a use case: success(value) and failure(errors) instead of RageArch::Result.success/failure.
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

      # Resolve a dep: first the injected one; if missing, use the container.
      # Optional: dep(:symbol, default: Implementation) when not registered.
      # If default is an Active Record model class (e.g. Order), it is wrapped automatically
      # with RageArch::Deps::ActiveRecord.for(default), so you can write dep(:order_store, default: Order).
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
