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

  describe "scope isolation" do
    it "scoped registrations override global ones" do
      described_class.register(:x, "global")
      described_class.push_scope
      described_class.register(:x, "scoped")
      expect(described_class.resolve(:x)).to eq "scoped"
      described_class.pop_scope
      expect(described_class.resolve(:x)).to eq "global"
    end

    it "falls back to global when not in scope" do
      described_class.register(:x, "global")
      described_class.push_scope
      expect(described_class.resolve(:x)).to eq "global"
      described_class.pop_scope
    end

    it "scoped registrations don't persist after pop" do
      described_class.push_scope
      described_class.register(:scoped_only, "val")
      expect(described_class.registered?(:scoped_only)).to eq true
      described_class.pop_scope
      expect(described_class.registered?(:scoped_only)).to eq false
    end

    it "nested scopes work correctly" do
      described_class.register(:x, "global")
      described_class.push_scope
      described_class.register(:x, "scope1")
      described_class.push_scope
      described_class.register(:x, "scope2")
      expect(described_class.resolve(:x)).to eq "scope2"
      described_class.pop_scope
      expect(described_class.resolve(:x)).to eq "scope1"
      described_class.pop_scope
      expect(described_class.resolve(:x)).to eq "global"
    end
  end
end
