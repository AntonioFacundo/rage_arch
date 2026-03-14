# frozen_string_literal: true

module RageArch
  # Simple in-process event publisher for domain events.
  # Use cases can subscribe via subscribe :event_name (or :all) in the use case class; wire with Base.wire_subscriptions_to(publisher).
  # Handlers (blocks, callables, or use case symbols) run synchronously. For subscribe :all, payload includes :event.
  #
  # Setup in config/initializers/rage_arch.rb:
  #   publisher = RageArch::EventPublisher.new
  #   RageArch::UseCase::Base.wire_subscriptions_to(publisher)
  #   RageArch.register(:event_publisher, publisher)
  class EventPublisher
    def initialize
      @handlers = Hash.new { |h, k| h[k] = [] }
      @publish_depth = 0
      @max_publish_depth = 100
    end

    # Subscribe to an event. Handler can be:
    # - A block: called with payload (Hash with symbol keys)
    # - A symbol: use case symbol; publisher runs UseCase::Base.build(symbol).call(payload)
    # - Any callable responding to call(payload)
    # For event_name :all, the payload passed to handlers includes :event (the name of the event being published).
    def subscribe(event_name, handler = nil, &block)
      callable = handler || block
      callable = use_case_runner(handler) if handler.is_a?(Symbol)
      raise ArgumentError, "Provide a block or a callable handler" unless callable
      @handlers[event_name.to_sym] << callable
      self
    end

    # Publish an event. Payload is passed as a Hash (symbol keys) to each handler.
    # Handlers for this event run first; then handlers for :all run with payload.merge(event: event_name).
    # Re-entrancy is limited to avoid infinite loops (e.g. a handler that publishes the same event).
    def publish(event_name, **payload)
      event_sym = event_name.to_sym
      @publish_depth += 1
      raise "Event publisher re-entrancy limit reached (possible circular publish)" if @publish_depth > @max_publish_depth
      begin
        @handlers[event_sym].each do |callable|
          callable.call(payload)
        end
        all_payload = payload.merge(event: event_sym)
        @handlers[:all].each do |callable|
          callable.call(all_payload)
        end
      ensure
        @publish_depth -= 1
      end
      nil
    end

    private

    def use_case_runner(symbol)
      ->(payload) { UseCase::Base.build(symbol).call(payload) }
    end
  end
end
