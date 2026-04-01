# frozen_string_literal: true

RSpec.describe RageArch::UseCase::Base do
  before do
    RageArch::Container.reset!
    described_class.registry.clear
  end

  let!(:use_case_class) do
    Class.new(described_class) do
      use_case_symbol :test_uc
      deps :dep_a

      def call(params = {})
        RageArch::Result.success(a: dep_a, params: params)
      end
    end
  end

  before do
    stub_const("TestUseCase", use_case_class)
  end

  describe ".use_case_symbol / .registry / .resolve" do
    it "registers the class by symbol" do
      expect(described_class.resolve(:test_uc)).to eq use_case_class
    end

    it "raises KeyError for unknown symbol" do
      expect { described_class.resolve(:unknown) }.to raise_error(KeyError, /unknown/)
    end
  end

  describe "convention-based symbol inference" do
    it "infers symbol from class name when not explicitly declared" do
      klass = Class.new(described_class) do
        def call(_p = {}); success(nil); end
      end
      stub_const("Appointments::Book", klass)
      expect(klass.use_case_symbol).to eq :appointments_book
      expect(described_class.registry[:appointments_book]).to eq klass
    end

    it "infers deeply nested symbol" do
      klass = Class.new(described_class) do
        def call(_p = {}); success(nil); end
      end
      stub_const("Admin::Reports::GenerateMonthly", klass)
      expect(klass.use_case_symbol).to eq :admin_reports_generate_monthly
    end

    it "explicit use_case_symbol overrides convention" do
      klass = Class.new(described_class) do
        use_case_symbol :my_custom_symbol
        def call(_p = {}); success(nil); end
      end
      stub_const("Payments::Charge", klass)
      expect(klass.use_case_symbol).to eq :my_custom_symbol
    end
  end

  describe ".build" do
    it "builds an instance injecting deps from the container" do
      RageArch::Container.register(:dep_a, "injected")
      uc = described_class.build(:test_uc)
      result = uc.call(hello: 1)
      expect(result.success?).to eq true
      expect(result.value[:a]).to eq "injected"
      expect(result.value[:params]).to eq(hello: 1)
    end

    it "raises KeyError when a required dep is not registered" do
      expect { described_class.build(:test_uc) }.to raise_error(KeyError)
    end
  end

  describe "deps macro" do
    it "makes deps private methods" do
      uc = use_case_class.new(dep_a: "val")
      expect { uc.dep_a }.to raise_error(NoMethodError)
    end

    it "injects multiple deps via constructor" do
      klass = Class.new(described_class) do
        use_case_symbol :multi_dep_uc
        deps :repo, :mailer
        def call(_p = {}); success(r: repo, m: mailer); end
      end
      stub_const("MultiDepUc", klass)
      result = klass.new(repo: "r", mailer: "m").call
      expect(result.value).to eq(r: "r", m: "m")
    end
  end

  describe "success/failure convenience methods" do
    it "success returns RageArch::Result.success" do
      RageArch::Container.register(:dep_a, "x")
      result = described_class.build(:test_uc).call
      expect(result).to be_a(RageArch::Result)
      expect(result.success?).to eq true
    end

    it "failure returns RageArch::Result.failure" do
      klass = Class.new(described_class) do
        use_case_symbol :fail_uc
        def call(_p = {}); failure(["bad"]); end
      end
      stub_const("FailUc", klass)
      result = klass.new.call
      expect(result).to be_a(RageArch::Result)
      expect(result.failure?).to eq true
      expect(result.errors).to eq ["bad"]
    end
  end

  describe "dep() instance method" do
    it "returns the injected dep by symbol" do
      klass = Class.new(described_class) do
        use_case_symbol :dep_instance_uc
        def call(_p = {}); success(dep(:custom)); end
      end
      stub_const("DepInstanceUc", klass)
      result = klass.new(custom: "injected").call
      expect(result.value).to eq "injected"
    end

    it "falls back to container when not injected" do
      klass = Class.new(described_class) do
        use_case_symbol :dep_container_uc
        def call(_p = {}); success(dep(:from_container)); end
      end
      stub_const("DepContainerUc", klass)
      RageArch::Container.register(:from_container, "from_container_val")
      expect(klass.new.call.value).to eq "from_container_val"
    end

    it "uses default when not injected and not in container" do
      klass = Class.new(described_class) do
        use_case_symbol :dep_default_uc
        def call(_p = {}); success(dep(:absent, default: "default_val")); end
      end
      stub_const("DepDefaultUc", klass)
      expect(klass.new.call.value).to eq "default_val"
    end

    it "raises KeyError when not injected, not in container, and no default" do
      klass = Class.new(described_class) do
        use_case_symbol :dep_missing_uc
        def call(_p = {}); dep(:totally_absent); end
      end
      stub_const("DepMissingUc", klass)
      expect { klass.new.call }.to raise_error(KeyError, /totally_absent/)
    end
  end

  describe "use_cases" do
    let!(:child_uc_class) do
      Class.new(described_class) do
        use_case_symbol :child_uc
        deps :dep_a
        def call(params = {}); RageArch::Result.success(echo: params[:x]); end
      end
    end

    let!(:parent_uc_class) do
      Class.new(described_class) do
        use_case_symbol :parent_uc
        deps :dep_a
        use_cases :child_uc
        def call(params = {})
          result = child_uc.call(x: params[:value])
          return result unless result.success?
          RageArch::Result.success(parent: true, child_echo: result.value[:echo])
        end
      end
    end

    before do
      stub_const("ChildUseCase", child_uc_class)
      stub_const("ParentUseCase", parent_uc_class)
      RageArch::Container.register(:dep_a, "dummy")
    end

    it "allows calling another use case by symbol and returns its Result" do
      result = described_class.build(:parent_uc).call(value: 42)
      expect(result.success?).to eq true
      expect(result.value[:parent]).to eq true
      expect(result.value[:child_echo]).to eq 42
    end

    it "makes the use case runner private" do
      instance = parent_uc_class.new(dep_a: "x")
      expect { instance.child_uc }.to raise_error(NoMethodError)
    end
  end

  describe "undo support" do
    it "calls undo on failure when undo is defined" do
      undo_called = false
      klass = Class.new(described_class) do
        use_case_symbol :undo_uc
        def call(_p = {}); failure(["oops"]); end
        define_method(:undo) { |_value| undo_called = true }
      end
      stub_const("UndoUc", klass)
      klass.new.call
      expect(undo_called).to eq true
    end

    it "does not call undo on success" do
      undo_called = false
      klass = Class.new(described_class) do
        use_case_symbol :undo_success_uc
        def call(_p = {}); success("ok"); end
        define_method(:undo) { |_value| undo_called = true }
      end
      stub_const("UndoSuccessUc", klass)
      klass.new.call
      expect(undo_called).to eq false
    end

    it "does nothing when undo is not defined and failure occurs" do
      klass = Class.new(described_class) do
        use_case_symbol :no_undo_uc
        def call(_p = {}); failure(["oops"]); end
      end
      stub_const("NoUndoUc", klass)
      expect { klass.new.call }.not_to raise_error
    end
  end

  describe "cascade undo via use_cases" do
    it "calls undo on child use cases in reverse order on parent failure" do
      undo_log = []

      child_a = Class.new(described_class) do
        use_case_symbol :child_a
        def call(_p = {}); success(step: :a); end
        define_method(:undo) { |_v| undo_log << :a }
      end

      child_b = Class.new(described_class) do
        use_case_symbol :child_b
        def call(_p = {}); success(step: :b); end
        define_method(:undo) { |_v| undo_log << :b }
      end

      parent = Class.new(described_class) do
        use_case_symbol :cascade_parent
        use_cases :child_a, :child_b
        def call(_p = {})
          child_a.call
          child_b.call
          failure(["parent failed"])
        end
      end

      stub_const("ChildA", child_a)
      stub_const("ChildB", child_b)
      stub_const("CascadeParent", parent)

      parent.new.call
      expect(undo_log).to eq [:b, :a]
    end

    it "only calls cascade undo on children that succeeded (failed children undo themselves)" do
      undo_log = []

      child_ok = Class.new(described_class) do
        use_case_symbol :child_ok
        def call(_p = {}); success(step: :ok); end
        define_method(:undo) { |_v| undo_log << :ok }
      end

      # child_no_undo fails but has no undo defined
      child_no_undo = Class.new(described_class) do
        use_case_symbol :child_no_undo
        def call(_p = {}); failure(["child failed"]); end
      end

      parent = Class.new(described_class) do
        use_case_symbol :cascade_partial
        use_cases :child_ok, :child_no_undo
        def call(_p = {})
          child_ok.call
          child_no_undo.call
          failure(["parent failed"])
        end
      end

      stub_const("ChildOk", child_ok)
      stub_const("ChildNoUndo", child_no_undo)
      stub_const("CascadePartial", parent)

      parent.new.call
      # child_ok succeeded and gets cascade-undone; child_no_undo failed and was never tracked
      expect(undo_log).to eq [:ok]
    end
  end

  describe "subscribe" do
    it "supports async: false option" do
      klass = Class.new(described_class) do
        use_case_symbol :sync_subscriber_uc
        subscribe :some_event, async: false
        def call(_p = {}); success(nil); end
      end
      stub_const("SyncSubscriberUc", klass)

      entries = klass.subscription_entries
      expect(entries).to eq [{ event: :some_event, async: false }]
      expect(klass.subscribed_events).to eq [:some_event]
    end

    it "defaults async to true" do
      klass = Class.new(described_class) do
        use_case_symbol :async_subscriber_uc
        subscribe :another_event
        def call(_p = {}); success(nil); end
      end
      stub_const("AsyncSubscriberUc", klass)

      entries = klass.subscription_entries
      expect(entries).to eq [{ event: :another_event, async: true }]
    end
  end

  describe "subscribe and wire_subscriptions_to" do
    let!(:subscriber_class) do
      Class.new(described_class) do
        use_case_symbol :subscriber_uc
        deps :dep_a
        subscribe :post_created, async: false

        def call(payload = {})
          RageArch::Result.success(echo: payload[:post_id])
        end
      end
    end

    before do
      stub_const("SubscriberUseCase", subscriber_class)
      RageArch::Container.register(:dep_a, "dummy")
    end

    it "wire_subscriptions_to registers use case as handler for subscribed events" do
      publisher = RageArch::EventPublisher.new
      described_class.wire_subscriptions_to(publisher)
      fake_uc = instance_double(described_class, call: RageArch::Result.success(ok: true))
      allow(described_class).to receive(:build).with(:subscriber_uc).and_return(fake_uc)
      publisher.publish(:post_created, post_id: 99)
      expect(fake_uc).to have_received(:call).with(post_id: 99)
    end
  end

  describe "skip_auto_publish" do
    it "skip_auto_publish? is true when skip_auto_publish was called" do
      klass = Class.new(described_class) do
        use_case_symbol :no_publish_uc
        skip_auto_publish
        def call(_params = {}); success(nil); end
      end
      stub_const("NoPublishUseCase", klass)
      expect(klass.skip_auto_publish?).to eq true
    end

    it "skip_auto_publish? is false by default" do
      expect(use_case_class.skip_auto_publish?).to eq false
    end
  end
end
