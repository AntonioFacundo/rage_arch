# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rage_arch"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
