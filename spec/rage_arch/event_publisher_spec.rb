# frozen_string_literal: true

RSpec.describe RageArch::EventPublisher do
  subject(:publisher) { described_class.new }

  describe "#subscribe and #publish" do
    it "calls block handlers with payload hash" do
      received = nil
      publisher.subscribe(:post_created) { |payload| received = payload }
      publisher.publish(:post_created, post_id: 1, user_id: 2)
      expect(received).to eq(post_id: 1, user_id: 2)
    end

    it "calls multiple handlers in order" do
      order = []
      publisher.subscribe(:ev) { order << :first }
      publisher.subscribe(:ev) { order << :second }
      publisher.publish(:ev)
      expect(order).to eq(%i[first second])
    end

    it "calls use case when handler is a symbol" do
      fake_uc = instance_double(RageArch::UseCase::Base, call: RageArch::Result.success(done: true))
      allow(RageArch::UseCase::Base).to receive(:build).with(:send_email).and_return(fake_uc)
      publisher.subscribe(:order_created, :send_email)
      publisher.publish(:order_created, order_id: 42)
      expect(fake_uc).to have_received(:call).with(order_id: 42)
    end

    it "calls :all handlers with payload including :event" do
      received = nil
      publisher.subscribe(:all) { |payload| received = payload }
      publisher.publish(:post_created, post_id: 1)
      expect(received[:event]).to eq(:post_created)
      expect(received[:post_id]).to eq(1)
    end

    it "does not raise when publishing to an event with no subscribers" do
      expect { publisher.publish(:nobody_listening, x: 1) }.not_to raise_error
    end

    it "publishes with empty payload by default" do
      received = :not_called
      publisher.subscribe(:ev) { |payload| received = payload }
      publisher.publish(:ev)
      expect(received).to eq({})
    end

    it "does not call handlers for different events" do
      called = false
      publisher.subscribe(:ev_a) { called = true }
      publisher.publish(:ev_b)
      expect(called).to eq false
    end

    it "raises on re-entrancy beyond the limit" do
      # A handler that re-publishes the same event causes infinite recursion
      publisher.subscribe(:loopy) { publisher.publish(:loopy) }
      expect { publisher.publish(:loopy) }.to raise_error(RuntimeError, /re-entrancy limit/)
    end
  end
end
