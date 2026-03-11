# frozen_string_literal: true

RSpec.describe RageArch::Result do
  describe ".success" do
    it "returns a result with success? true and the value" do
      r = described_class.success(42)
      expect(r.success?).to eq true
      expect(r.failure?).to eq false
      expect(r.value).to eq 42
      expect(r.errors).to eq []
    end

    it "accepts nil value" do
      r = described_class.success(nil)
      expect(r.success?).to eq true
      expect(r.value).to be_nil
    end

    it "returns empty errors array" do
      expect(described_class.success(42).errors).to eq []
    end
  end

  describe ".failure" do
    it "returns a result with failure? true and the errors" do
      r = described_class.failure(["Something failed"])
      expect(r.failure?).to eq true
      expect(r.success?).to eq false
      expect(r.value).to be_nil
      expect(r.errors).to eq ["Something failed"]
    end

    it "converts a hash to an array of pairs" do
      r = described_class.failure(email: "is invalid", name: "is blank")
      expect(r.failure?).to eq true
      expect(r.errors).to include([:email, "is invalid"], [:name, "is blank"])
    end

    it "wraps a single string in an array" do
      expect(described_class.failure("oops").errors).to eq ["oops"]
    end

    it "keeps an array of strings as-is" do
      expect(described_class.failure(["a", "b"]).errors).to eq ["a", "b"]
    end
  end
end
