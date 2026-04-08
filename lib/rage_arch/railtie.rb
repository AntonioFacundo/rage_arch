# frozen_string_literal: true

require "rage_arch"
require_relative "controller"
require_relative "patches/middleware_stack"

module RageArch
  class Railtie < ::Rails::Railtie
    config.rage_arch = ActiveSupport::OrderedOptions.new
    config.rage_arch.auto_publish_events = true
    config.rage_arch.verify_deps = true
    config.rage_arch.async_subscribers = true

    # Load use case and dep files, then auto-register by convention.
    initializer "rage_arch.auto_register", after: :eager_load! do |app|
      next if ENV["SECRET_KEY_BASE_DUMMY"].present?

      # Load use case files so they register their symbols in the registry.
      use_cases_dir = app.root.join("app/use_cases")
      if use_cases_dir.exist?
        Dir[use_cases_dir.join("**/*.rb")].sort.each { |f| require f }
      end

      # Auto-register use cases and deps by convention.
      RageArch::AutoRegistry.run
    end
  end
end
