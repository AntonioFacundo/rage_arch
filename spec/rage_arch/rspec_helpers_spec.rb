# frozen_string_literal: true

require "rage_arch/rspec_helpers"

RSpec.describe RageArch::RSpecHelpers do
  before { RageArch::Container.reset! }

  context "when included in an example group" do
    # Create a nested example group that includes RSpecHelpers
    let(:example_group) do
      RSpec.describe "inner group" do
        include RageArch::RSpecHelpers

        it "registers inside isolate" do
          RageArch.register(:scoped_dep, "scoped_value")
          expect(RageArch.resolve(:scoped_dep)).to eq "scoped_value"
        end
      end
    end

    it "does not leak scoped registrations to outer context" do
      RageArch.register(:outer, "outer_value")

      # Run the inner example group
      example_group.run

      # Scoped registration should not leak
      expect(RageArch.registered?(:scoped_dep)).to eq false
      # Outer registration should remain
      expect(RageArch.resolve(:outer)).to eq "outer_value"
    end
  end

  it "restores state after each example even on failure" do
    RageArch.register(:persistent, "original")

    # Simulate what RSpecHelpers does: isolate wraps and restores on exception
    begin
      RageArch.isolate do
        RageArch.register(:persistent, "overridden")
        expect(RageArch.resolve(:persistent)).to eq "overridden"
        raise "intentional failure"
      end
    rescue RuntimeError
      # expected
    end

    expect(RageArch.resolve(:persistent)).to eq "original"
  end
end
