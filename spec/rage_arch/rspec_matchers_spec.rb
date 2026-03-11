# frozen_string_literal: true

require "rage_arch/rspec_matchers"

RSpec.describe "RageArch::RSpecMatchers" do
  describe "succeed_with" do
    it "passes when result is success and value matches hash" do
      result = RageArch::Result.success(post: 1, user: 2)
      expect(result).to succeed_with(post: 1, user: 2)
      expect(result).to succeed_with(post: 1)
    end

    it "passes when result is success and single value matches" do
      result = RageArch::Result.success(42)
      expect(result).to succeed_with(42)
    end

    it "passes with composable matchers" do
      result = RageArch::Result.success(post: double("Post", id: 1), count: 2)
      expect(result).to succeed_with(post: a_kind_of(RSpec::Mocks::Double), count: 2)
    end

    it "fails when result is failure" do
      result = RageArch::Result.failure(["error"])
      expect(result).not_to succeed_with(anything)
      expect { expect(result).to succeed_with(a: 1) }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /expected success but got failure/)
    end

    it "fails when value does not match" do
      result = RageArch::Result.success(a: 1, b: 2)
      expect(result).not_to succeed_with(a: 99)
      expect(result).not_to succeed_with(42)
    end
  end

  describe "fail_with_errors" do
    it "passes when result is failure and errors match" do
      result = RageArch::Result.failure(["not found", "invalid"])
      expect(result).to fail_with_errors(["not found", "invalid"])
      expect(result).to fail_with_errors(include("not found"))
    end

    it "fails when result is success" do
      result = RageArch::Result.success(1)
      expect(result).not_to fail_with_errors(["x"])
      expect { expect(result).to fail_with_errors(["x"]) }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /expected failure but got success/)
    end

    it "fails when errors do not match" do
      result = RageArch::Result.failure(["a"])
      expect(result).not_to fail_with_errors(["b"])
    end
  end
end
