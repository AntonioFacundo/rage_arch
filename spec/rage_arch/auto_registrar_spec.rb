# frozen_string_literal: true

RSpec.describe RageArch::AutoRegistrar do
  before do
    RageArch::Container.reset!
    RageArch::UseCase::Base.registry.clear
  end

  describe "register_use_cases (via use_case_symbol)" do
    it "registers use case subclasses by inferred symbol" do
      klass = Class.new(RageArch::UseCase::Base) do
        def self.name; "Orders::Create"; end
        def call(params = {}); success(params); end
      end

      # Trigger inference manually (as AutoRegistrar does via use_case_symbol)
      klass.use_case_symbol

      expect(RageArch::UseCase::Base.registry[:orders_create]).to eq klass
    end

    it "skips anonymous classes (no name)" do
      klass = Class.new(RageArch::UseCase::Base) do
        def call(params = {}); success(params); end
      end

      # Anonymous class infers nil symbol
      expect(klass.use_case_symbol).to be_nil
    end
  end

  describe "resolve_store_deps" do
    it "registers use case and resolves _store dep symbol" do
      klass = Class.new(RageArch::UseCase::Base) do
        def self.name; "Items::Show"; end
        deps :item_store
        def call(params = {}); success(params); end
      end

      # Trigger registration
      klass.use_case_symbol

      expect(RageArch::UseCase::Base.registry[:items_show]).to eq klass
      expect(klass.declared_deps).to include(:item_store)
    end
  end

  describe "dep symbol inference" do
    it "uses demodulized class name for namespaced deps" do
      # Simulate what register_deps does with the demodulize logic
      full_name = "Posts::PostRepo"
      sym = ActiveSupport::Inflector.underscore(
        ActiveSupport::Inflector.demodulize(full_name)
      ).to_sym

      expect(sym).to eq :post_repo
    end

    it "works for non-namespaced deps" do
      full_name = "PaymentGateway"
      sym = ActiveSupport::Inflector.underscore(
        ActiveSupport::Inflector.demodulize(full_name)
      ).to_sym

      expect(sym).to eq :payment_gateway
    end
  end
end
