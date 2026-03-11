# frozen_string_literal: true

require "rage_arch/controller"

RSpec.describe RageArch::Controller do
  let(:flash_now) { {} }
  let(:flash_obj) { double("flash", now: flash_now) }

  let(:controller) do
    cls = Class.new do
      include RageArch::Controller
      public :run, :run_result, :flash_errors
    end
    instance = cls.new
    allow(instance).to receive(:flash).and_return(flash_obj)
    instance
  end

  let(:success_result) { RageArch::Result.success(user: double("user")) }
  let(:failure_result) { RageArch::Result.failure(["something went wrong"]) }

  before do
    RageArch::Container.reset!
    RageArch::UseCase::Base.registry.clear
  end

  def register_use_case(symbol, result)
    klass = Class.new(RageArch::UseCase::Base) do
      define_method(:call) { |_p = {}| result }
    end
    klass.use_case_symbol(symbol)
    stub_const("FakeUc#{symbol.to_s.capitalize}", klass)
  end

  describe "#run_result" do
    it "builds and calls the use case, returning the Result" do
      register_use_case(:get_thing, success_result)
      result = controller.run_result(:get_thing, { id: 1 })
      expect(result).to eq success_result
    end
  end

  describe "#run" do
    it "calls the success lambda on success" do
      register_use_case(:ok_thing, success_result)
      called_with = nil
      controller.run(:ok_thing, {},
        success: ->(r) { called_with = r },
        failure: ->(_r) { raise "should not call failure" })
      expect(called_with).to eq success_result
    end

    it "calls the failure lambda on failure" do
      register_use_case(:fail_thing, failure_result)
      called_with = nil
      controller.run(:fail_thing, {},
        success: ->(_r) { raise "should not call success" },
        failure: ->(r) { called_with = r })
      expect(called_with).to eq failure_result
    end
  end

  describe "#flash_errors" do
    it "sets flash.now[:alert] to joined errors" do
      controller.flash_errors(failure_result)
      expect(flash_now[:alert]).to eq "something went wrong"
    end

    it "joins multiple errors with a comma" do
      result = RageArch::Result.failure(["err1", "err2"])
      controller.flash_errors(result)
      expect(flash_now[:alert]).to eq "err1, err2"
    end
  end
end
