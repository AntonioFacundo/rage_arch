# frozen_string_literal: true

module RageArch
  # Include in ApplicationController to get run(symbol, params, success:, failure:) and
  # flash_errors(result). Keeps controllers thin: symbol, params, and HTTP responses only.
  module Controller
    private

    def run(symbol, params = {}, success:, failure:)
      result = run_result(symbol, params)
      (result.success? ? success : failure).call(result)
    end

    def run_result(symbol, params = {})
      RageArch::UseCase::Base.build(symbol).call(params)
    end

    def flash_errors(result)
      flash.now[:alert] = result.errors.join(", ")
    end
  end
end
