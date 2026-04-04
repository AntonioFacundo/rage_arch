# frozen_string_literal: true

module RageArch
  # Auto-registers use cases and deps at boot by convention.
  # Use cases: subclasses of RageArch::UseCase::Base → registered by inferred symbol.
  # Deps: classes under app/deps/ → registered by inferred symbol.
  # AR auto-resolution: deps ending in _store with no file in app/deps/ → resolves AR model.
  class AutoRegistrar
    class << self
      def run
        register_use_cases
        register_deps
        resolve_store_deps
      end

      private

      def register_use_cases
        RageArch::UseCase::Base.registry.each do |sym, _klass|
          # Already in registry via use_case_symbol or infer_use_case_symbol — nothing to do.
          # The act of calling use_case_symbol (explicit or inferred) registers the class.
        end

        # Ensure all subclasses have their symbol inferred and registered
        RageArch::UseCase::Base.descendants.each do |klass|
          next if klass.name.nil? # anonymous classes
          klass.use_case_symbol # triggers inference + registration if not already set
        end
      end

      def register_deps
        return unless defined?(Rails) && Rails.application

        deps_dir = Rails.root.join("app", "deps")
        return unless deps_dir.exist?

        Dir[deps_dir.join("**/*.rb")].sort.each do |file|
          require file
        end

        # Register any class defined under app/deps/ that isn't already registered
        ObjectSpace.each_object(Class).select do |klass|
          next unless klass.name
          next if klass.name.start_with?("RageArch::")

          # Check if this class was loaded from app/deps/
          source_file = begin
            Object.const_source_location(klass.name)&.first
          rescue
            nil
          end
          next unless source_file && source_file.start_with?(deps_dir.to_s)

          sym = ActiveSupport::Inflector.underscore(ActiveSupport::Inflector.demodulize(klass.name)).to_sym
          unless Container.registered?(sym)
            begin
              Container.register(sym, klass.new)
            rescue LoadError, StandardError => e
              # Skip deps that fail to instantiate (e.g. missing gem dependencies).
              # These are typically alternative implementations not currently active.
            end
          end
        end
      end

      def resolve_store_deps
        # For each use case, check declared deps ending in _store
        RageArch::UseCase::Base.registry.each_value do |klass|
          klass.declared_deps.each do |dep_sym|
            next if Container.registered?(dep_sym)
            next unless dep_sym.to_s.end_with?("_store")

            model_name = dep_sym.to_s.sub(/_store\z/, "").camelize
            model_class = begin
              model_name.constantize
            rescue NameError
              nil
            end

            if model_class && defined?(ActiveRecord::Base) && model_class < ActiveRecord::Base
              Container.register(dep_sym, Deps::ActiveRecord.for(model_class))
            end
          end
        end
      end
    end
  end
end
