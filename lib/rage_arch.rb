# frozen_string_literal: true

require_relative "rage_arch/version"
require_relative "rage_arch/result"
require_relative "rage_arch/container"
require_relative "rage_arch/dep"
require_relative "rage_arch/event_publisher"
require_relative "rage_arch/use_case"
require_relative "rage_arch/deps/active_record"
require_relative "rage_arch/dep_scanner"
require_relative "rage_arch/auto_registrar"

module RageArch
  class << self
    def register(symbol, implementation = nil, &block)
      Container.register(symbol, implementation, &block)
    end

    # Registers a dep that uses Active Record for the given model.
    # Example: RageArch.register_ar(:user_store, User)
    def register_ar(symbol, model_class)
      register(symbol, Deps::ActiveRecord.for(model_class))
    end

    def resolve(symbol)
      Container.resolve(symbol)
    end

    def registered?(symbol)
      Container.registered?(symbol)
    end

    # Wraps execution in a sandboxed container scope.
    # Registrations inside the block are scoped; originals are restored on exit.
    def isolate(&block)
      Container.push_scope
      yield
    ensure
      Container.pop_scope
    end

    # Verifies that all deps and use_cases declared by registered use cases are
    # available before the app handles any request. Call after all initializers run
    # (done automatically by the Railtie unless config.rage_arch.verify_deps = false).
    #
    # Raises RuntimeError listing every missing dep/use_case if any are absent.
    # Returns true when everything is wired correctly.
    def verify_deps!
      errors = []
      warnings = []
      scanned_methods = DepScanner.new.scan

      UseCase::Base.registry.each do |uc_symbol, klass|
        # 6a. Symbol/convention mismatch warning
        if klass.name
          inferred = ActiveSupport::Inflector.underscore(klass.name).gsub("/", "_").to_sym
          explicit = klass.instance_variable_get(:@use_case_symbol)
          if explicit && explicit != inferred
            warnings << "  #{klass} declares use_case_symbol :#{explicit} but convention infers :#{inferred} — explicit declaration overrides convention"
          end
        end

        # 6c. Orphaned undo warning: undo defined but no call method
        if klass.method_defined?(:undo) && !klass.method_defined?(:call, false)
          warnings << "  #{klass} defines undo but has no call method"
        end

        klass.declared_deps.uniq.each do |dep_sym|
          unless Container.registered?(dep_sym)
            # 6b. AR model not found for _store dep
            if dep_sym.to_s.end_with?("_store")
              errors << "  UseCase :#{uc_symbol} (#{klass}) declares dep :#{dep_sym} — not registered in container and no AR model found"
            else
              errors << "  UseCase :#{uc_symbol} (#{klass}) declares dep :#{dep_sym} — not registered in container"
            end
            next
          end

          required_methods = scanned_methods[dep_sym]
          next if required_methods.nil? || required_methods.empty?

          entry = Container.registry[dep_sym]
          entry = Container.send(:scoped_lookup, dep_sym) if entry.nil?
          impl =
            if entry.is_a?(Class)
              entry
            elsif entry.is_a?(Proc)
              nil # skip: calling a Proc may have side effects
            else
              entry
            end

          next if impl.nil?

          impl_name = impl.is_a?(Class) ? impl.name : impl.class.name

          required_methods.each do |method_name|
            has_method =
              if impl.is_a?(Class)
                impl.method_defined?(method_name) || impl.respond_to?(method_name)
              else
                impl.respond_to?(method_name)
              end

            unless has_method
              errors << "  UseCase :#{uc_symbol} (#{klass}) calls dep :#{dep_sym}##{method_name} — #{impl_name} does not implement ##{method_name}"
            end
          end
        end

        klass.declared_use_cases.uniq.each do |ref_sym|
          next if UseCase::Base.registry.key?(ref_sym)

          errors << "  UseCase :#{uc_symbol} (#{klass}) declares use_cases :#{ref_sym} — not registered in use case registry"
        end
      end

      # Log warnings (non-fatal)
      if warnings.any? && defined?(Rails) && Rails.logger
        warnings.each { |w| Rails.logger.warn("[RageArch] #{w.strip}") }
      end

      raise "RageArch boot verification failed:\n#{errors.join("\n")}" if errors.any?

      true
    end
  end
end

require_relative "rage_arch/controller" if defined?(Rails)
require "rage_arch/railtie" if defined?(Rails)
