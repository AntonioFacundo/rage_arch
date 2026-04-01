# frozen_string_literal: true

module RageArch
  # Container to register and resolve dependencies by symbol.
  # Supports scoped isolation via RageArch.isolate for test environments.
  class Container
    class << self
      def register(symbol, implementation = nil, &block)
        if current_scope
          current_scope[symbol] = block || implementation
        else
          registry[symbol] = block || implementation
        end
      end

      def resolve(symbol)
        entry = scoped_lookup(symbol)
        raise KeyError, "Dep not registered: #{symbol.inspect}" unless entry

        if entry.respond_to?(:call) && entry.is_a?(Proc)
          entry.call
        elsif entry.is_a?(Class)
          entry.new
        else
          entry
        end
      end

      def registered?(symbol)
        return true if current_scope&.key?(symbol)
        registry.key?(symbol)
      end

      def registry
        @registry ||= {}
      end

      def reset!
        @registry = {}
      end

      # --- Scope isolation for tests ---

      def push_scope
        scope_stack.push({})
      end

      def pop_scope
        scope_stack.pop
      end

      private

      def scope_stack
        Thread.current[:rage_arch_container_scopes] ||= []
      end

      def current_scope
        scope_stack.last
      end

      def scoped_lookup(symbol)
        if current_scope&.key?(symbol)
          current_scope[symbol]
        else
          registry[symbol]
        end
      end
    end
  end
end
