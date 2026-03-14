# frozen_string_literal: true

module RageArch
  # Container to register and resolve dependencies by symbol.
  # Usage: RageArch.register(:order_store, MyAdapter.new); RageArch.resolve(:order_store)
  class Container
    class << self
      def register(symbol, implementation = nil, &block)
        registry[symbol] = block || implementation
      end

      def resolve(symbol)
        entry = registry[symbol]
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
        registry.key?(symbol)
      end

      def registry
        @registry ||= {}
      end

      def reset!
        @registry = {}
      end
    end
  end
end
