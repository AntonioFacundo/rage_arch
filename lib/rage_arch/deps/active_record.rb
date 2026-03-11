# frozen_string_literal: true

module RageArch
  module Deps
    # Helper to use an Active Record model as a dep (minimal adapter).
    # Usage: RageArch::Deps::ActiveRecord.for(Order) → object exposing build, find, etc. on Order.
    # In the container: Rage.register(:order_store, RageArch::Deps::ActiveRecord.for(Order))
    class ActiveRecord
      def self.for(model_class)
        new(model_class)
      end

      def initialize(model_class)
        @model_class = model_class
      end

      def find(id)
        @model_class.find_by(id: id)
      end

      def build(attrs = {})
        @model_class.new(attrs)
      end

      def save(record)
        record.save
      end

      def update(record, attrs)
        record.assign_attributes(attrs)
        record.save
      end

      def destroy(record)
        record.destroy
      end

      def list(filters: {})
        scope = @model_class.all
        filters.each { |key, value| scope = scope.where(key => value) if value.present? }
        scope.to_a
      end
    end
  end
end
