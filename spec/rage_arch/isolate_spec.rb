# frozen_string_literal: true

RSpec.describe "RageArch.isolate" do
  before { RageArch::Container.reset! }

  it "isolates registrations within the block" do
    RageArch.register(:x, "global")

    RageArch.isolate do
      RageArch.register(:x, "isolated")
      expect(RageArch.resolve(:x)).to eq "isolated"
    end

    expect(RageArch.resolve(:x)).to eq "global"
  end

  it "restores state even when block raises" do
    RageArch.register(:x, "global")

    begin
      RageArch.isolate do
        RageArch.register(:x, "isolated")
        raise "boom"
      end
    rescue RuntimeError
      # expected
    end

    expect(RageArch.resolve(:x)).to eq "global"
  end

  it "scoped-only registrations don't leak" do
    RageArch.isolate do
      RageArch.register(:temp, "temporary")
      expect(RageArch.registered?(:temp)).to eq true
    end

    expect(RageArch.registered?(:temp)).to eq false
  end
end
