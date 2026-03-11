# frozen_string_literal: true

module RageArch
  # Event publisher that records all published events for tests. Does not run any handlers.
  # Use it to assert that a use case (or code) published expected events.
  #
  #   publisher = RageArch::FakeEventPublisher.new
  #   Rage.register(:event_publisher, publisher)
  #   RageArch::UseCase::Base.build(:create_post).call(title: "Hi")
  #   expect(publisher.published).to include(
  #     hash_including(event: :post_created, post_id: kind_of(Integer))
  #   )
  #   publisher.clear  # optional: reset between examples
  class FakeEventPublisher
    attr_reader :published

    def initialize
      @published = []
    end

    # Same signature as EventPublisher#publish. Records the event and payload; does not run handlers.
    def publish(event_name, **payload)
      @published << { event: event_name.to_sym, payload: payload }
      nil
    end

    def subscribe(_event_name, _handler = nil, &_block)
      # No-op: we don't run handlers in tests
      self
    end

    def clear
      @published.clear
      self
    end
  end
end
