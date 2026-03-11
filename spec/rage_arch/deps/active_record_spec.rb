# frozen_string_literal: true

require "active_support/core_ext/object/blank"

RSpec.describe RageArch::Deps::ActiveRecord do
  let(:record)      { double("record") }
  let(:model_class) { double("ModelClass") }
  subject(:adapter) { described_class.for(model_class) }

  describe ".for" do
    it "returns an instance wrapping the model class" do
      expect(adapter).to be_a(described_class)
    end
  end

  describe "#find" do
    it "delegates to model_class.find_by(id:)" do
      allow(model_class).to receive(:find_by).with(id: 1).and_return(record)
      expect(adapter.find(1)).to eq record
    end

    it "returns nil when not found" do
      allow(model_class).to receive(:find_by).and_return(nil)
      expect(adapter.find(99)).to be_nil
    end
  end

  describe "#build" do
    it "delegates to model_class.new with attrs" do
      allow(model_class).to receive(:new).and_return(record)
      expect(adapter.build(name: "foo")).to eq record
      expect(model_class).to have_received(:new).with({ name: "foo" })
    end

    it "delegates with no attrs" do
      allow(model_class).to receive(:new).and_return(record)
      expect(adapter.build).to eq record
    end
  end

  describe "#save" do
    it "calls save on the record and returns the result" do
      allow(record).to receive(:save).and_return(true)
      expect(adapter.save(record)).to eq true
    end

    it "returns false when save fails" do
      allow(record).to receive(:save).and_return(false)
      expect(adapter.save(record)).to eq false
    end
  end

  describe "#update" do
    it "assigns attributes and saves the record" do
      allow(record).to receive(:assign_attributes)
      allow(record).to receive(:save).and_return(true)
      expect(adapter.update(record, name: "bar")).to eq true
      expect(record).to have_received(:assign_attributes).with({ name: "bar" })
    end

    it "returns false when save fails after assign" do
      allow(record).to receive(:assign_attributes)
      allow(record).to receive(:save).and_return(false)
      expect(adapter.update(record, name: "x")).to eq false
    end
  end

  describe "#destroy" do
    it "calls destroy on the record" do
      allow(record).to receive(:destroy).and_return(record)
      expect(adapter.destroy(record)).to eq record
    end
  end

  describe "#list" do
    let(:scope) { double("scope") }

    before do
      allow(model_class).to receive(:all).and_return(scope)
      allow(scope).to receive(:to_a).and_return([record])
    end

    it "returns all records when no filters given" do
      expect(adapter.list).to eq [record]
    end

    it "applies present filters via where" do
      filtered_scope = double("filtered_scope", to_a: [record])
      allow(scope).to receive(:where).and_return(filtered_scope)
      result = adapter.list(filters: { status: "active" })
      expect(result).to eq [record]
      expect(scope).to have_received(:where).with({ status: "active" })
    end

    it "skips blank filter values" do
      expect(scope).not_to receive(:where)
      adapter.list(filters: { status: nil })
    end
  end
end
