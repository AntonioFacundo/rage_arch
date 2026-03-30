# frozen_string_literal: true

require "rage_arch"
require_relative "controller"

module RageArch
  class Railtie < ::Rails::Railtie
    config.rage_arch = ActiveSupport::OrderedOptions.new
    config.rage_arch.auto_publish_events = true
    config.rage_arch.verify_deps = true

    # Load use case files so they register their symbols in the registry.
    # Without this, build(:symbol) would fail until the use case constant was referenced.
    config.after_initialize do |app|
      # Skip everything during asset precompilation — no deps are registered then.
      next if ENV["SECRET_KEY_BASE_DUMMY"].present?

      use_cases_dir = app.root.join("app/use_cases")
      if use_cases_dir.exist?
        Dir[use_cases_dir.join("**/*.rb")].sort.each { |f| require f }
      end

      # NOTE: verify_deps! is intentionally NOT called here. This after_initialize
      # runs before the app's own initializers' after_initialize blocks, so deps
      # registered there would not be visible yet. Apps should call
      # RageArch.verify_deps! manually at the end of their own after_initialize
      # (config/initializers/rage_arch.rb), after all deps are registered.
      # Set config.rage_arch.verify_deps = false to opt out.
    end
  end
end
