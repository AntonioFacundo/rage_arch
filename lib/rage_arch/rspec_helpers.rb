# frozen_string_literal: true

module RageArch
  # RSpec helper that wraps each example in RageArch.isolate,
  # preventing test pollution from dep registrations.
  #
  # Usage in spec/rails_helper.rb:
  #   require "rage_arch/rspec_helpers"
  #   RSpec.configure do |config|
  #     config.include RageArch::RSpecHelpers
  #   end
  module RSpecHelpers
    def self.included(base)
      base.around(:each) do |example|
        RageArch.isolate { example.run }
      end
    end
  end
end
