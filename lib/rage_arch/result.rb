# frozen_string_literal: true

module RageArch
  # Result object for an operation: success (with value) or failure (with errors).
  # Controllers use result.success?, result.value, and result.errors.
  class Result
    def self.success(value)
      new(success: true, value: value, errors: [])
    end

    def self.failure(errors)
      new(success: false, value: nil, errors: Array(errors))
    end

    attr_reader :value, :errors

    def initialize(success:, value:, errors:)
      @success = success
      @value = value
      @errors = errors
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end
end
