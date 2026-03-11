# frozen_string_literal: true

require_relative "rage_arch/version"
require_relative "rage_arch/result"
require_relative "rage_arch/container"
require_relative "rage_arch/dep"
require_relative "rage_arch/event_publisher"
require_relative "rage_arch/use_case"
require_relative "rage_arch/deps/active_record"
require_relative "rage_arch/dep_scanner"

module RageArch
  class << self
    def register(symbol, implementation = nil, &block)
      Container.register(symbol, implementation, &block)
    end

    # Registers a dep that uses Active Record for the given model.
    # Example: Rage.register_ar(:user_store, User)
    def register_ar(symbol, model_class)
      register(symbol, Deps::ActiveRecord.for(model_class))
    end

    def resolve(symbol)
      Container.resolve(symbol)
    end

    def registered?(symbol)
      Container.registered?(symbol)
    end

    # Verifies that all deps and use_cases declared by registered use cases are
    # available before the app handles any request. Call after all initializers run
    # (done automatically by the Railtie unless config.rage.verify_deps = false).
    #
    # Raises RuntimeError listing every missing dep/use_case if any are absent.
    # Returns true when everything is wired correctly.
    def verify_deps!
      errors = []
      scanned_methods = DepScanner.new.scan

      UseCase::Base.registry.each do |uc_symbol, klass|
        klass.declared_deps.uniq.each do |dep_sym|
          next if klass.ar_deps.key?(dep_sym) # ar_deps fall back to ActiveRecord, optional

          unless Container.registered?(dep_sym)
            errors << "  UseCase :#{uc_symbol} (#{klass}) declares dep :#{dep_sym} — not registered in container"
            next
          end

          required_methods = scanned_methods[dep_sym]
          next if required_methods.nil? || required_methods.empty?

          entry = Container.registry[dep_sym]
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

      raise "RageArch boot verification failed:\n#{errors.join("\n")}" if errors.any?

      true
    end
  end
end

require_relative "rage_arch/controller" if defined?(Rails)
require "rage_arch/railtie" if defined?(Rails)
