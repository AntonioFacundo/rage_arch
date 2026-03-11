# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rage_arch/version"
require "rage_arch/result"
require "rage_arch/container"
require "rage_arch/dep"
require "rage_arch/dep_scanner"
require "rage_arch/event_publisher"
require "rage_arch/use_case"
require "rage_arch/deps/active_record"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
