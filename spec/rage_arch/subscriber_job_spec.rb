# frozen_string_literal: true

require "active_job"
require "rage_arch/fake_event_publisher"
require "rage_arch/subscriber_job"

# Minimal ActiveJob setup for testing (no Rails needed)
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

RSpec.describe RageArch::SubscriberJob do
  before do
    RageArch::Container.reset!
    RageArch::UseCase::Base.registry.clear
  end

  let(:job) { described_class.new }

  it "inherits from ActiveJob::Base" do
    expect(described_class).to be < ActiveJob::Base
  end

  it "uses the default queue" do
    expect(described_class.queue_name).to eq "default"
  end

  it "builds and calls the use case with symbolized payload" do
    klass = Class.new(RageArch::UseCase::Base) do
      def call(params = {})
        success(received: params)
      end
    end
    klass.use_case_symbol :test_subscriber

    RageArch.register(:event_publisher, RageArch::FakeEventPublisher.new)

    # Simulate what ActiveJob serialization does: string keys
    job.perform("test_subscriber", { "user_id" => 42, "action" => "created" })

    result = RageArch::UseCase::Base.build(:test_subscriber).call(user_id: 42)
    expect(result).to be_success
  end

  it "converts string keys to symbols in payload" do
    received_params = nil
    klass = Class.new(RageArch::UseCase::Base) do
      define_method(:call) do |params = {}|
        received_params = params
        success(params)
      end
    end
    klass.use_case_symbol :key_test

    RageArch.register(:event_publisher, RageArch::FakeEventPublisher.new)

    job.perform("key_test", { "name" => "test", "count" => 5 })

    expect(received_params).to eq({ name: "test", count: 5 })
  end

  it "raises when use case symbol is not registered" do
    expect { job.perform("nonexistent", {}) }.to raise_error(KeyError)
  end
end
