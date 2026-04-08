# frozen_string_literal: true

# Ruby 4.0+ freezes array literals by default. ActionPack's MiddlewareStack#build
# calls `middlewares.freeze` which permanently freezes the internal array,
# preventing later initializers (e.g. Propshaft) from inserting middleware.
#
# This patch makes `build` freeze a dup instead of the original array.
if RUBY_VERSION >= '4.0'
  require 'action_dispatch/middleware/stack'

  ActionDispatch::MiddlewareStack.prepend(Module.new do
    def build(app = nil, &block)
      duped = middlewares.dup
      duped.freeze.reverse.inject(app || block) do |a, e|
        e.build(a)
      end
    end
  end)
end
