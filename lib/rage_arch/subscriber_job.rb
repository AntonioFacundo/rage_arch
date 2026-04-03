# frozen_string_literal: true

module RageArch
  class SubscriberJob < ActiveJob::Base
    queue_as :default

    def perform(subscriber_symbol, payload)
      sym = subscriber_symbol.to_sym
      payload = payload.transform_keys(&:to_sym) if payload.is_a?(Hash)
      RageArch::UseCase::Base.build(sym).call(payload)
    end
  end
end
