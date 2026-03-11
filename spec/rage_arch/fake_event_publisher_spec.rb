# frozen_string_literal: true

require "rage_arch/fake_event_publisher"

RSpec.describe RageArch::FakeEventPublisher do
  subject(:publisher) { described_class.new }

  describe "#publish" do
    it "records event and payload without running handlers" do
      publisher.publish(:post_created, post_id: 1, user_id: 2)
      expect(publisher.published).to eq([
        { event: :post_created, payload: { post_id: 1, user_id: 2 } }
      ])
    end

    it "records multiple publishes in order" do
      publisher.publish(:a)
      publisher.publish(:b, x: 1)
      expect(publisher.published.size).to eq 2
      expect(publisher.published[0][:event]).to eq :a
      expect(publisher.published[1][:event]).to eq :b
      expect(publisher.published[1][:payload]).to eq(x: 1)
    end
  end

  describe "#subscribe" do
    it "is a no-op and returns self" do
      publisher.subscribe(:ev) { raise "should not run" }
      publisher.publish(:ev)
      expect(publisher.published).to eq([{ event: :ev, payload: {} }])
    end
  end

  describe "#clear" do
    it "clears recorded events" do
      publisher.publish(:a)
      publisher.clear
      expect(publisher.published).to eq []
    end
  end
end
