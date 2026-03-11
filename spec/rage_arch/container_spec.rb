# frozen_string_literal: true

RSpec.describe RageArch::Container do
  before { described_class.reset! }

  describe ".register / .resolve" do
    it "registers and resolves by symbol" do
      obj = Object.new
      described_class.register(:foo, obj)
      expect(described_class.resolve(:foo)).to eq obj
    end

    it "resolves a block" do
      described_class.register(:bar) { "result" }
      expect(described_class.resolve(:bar)).to eq "result"
    end

    it "overwrites an existing registration" do
      described_class.register(:x, "first")
      described_class.register(:x, "second")
      expect(described_class.resolve(:x)).to eq "second"
    end

    it "raises KeyError when symbol is not registered" do
      expect { described_class.resolve(:nonexistent) }.to raise_error(KeyError, /nonexistent/)
    end
  end

  describe ".registered?" do
    it "returns true when registered" do
      described_class.register(:x, 1)
      expect(described_class.registered?(:x)).to eq true
    end

    it "returns false when not registered" do
      expect(described_class.registered?(:y)).to eq false
    end
  end

  describe ".reset!" do
    it "clears all registrations" do
      described_class.register(:a, 1)
      described_class.reset!
      expect(described_class.registered?(:a)).to eq false
    end
  end
end
