# frozen_string_literal: true

require_relative "lib/rage_arch/version"

Gem::Specification.new do |spec|
  spec.name    = "rage_arch"
  spec.version = RageArch::VERSION
  spec.authors = ["Rage Corp"]
  spec.email   = ["antonio.facundo1794@gmail.com"]

  spec.summary     = "Convention-over-configuration Clean Architecture for Rails."
  spec.description = "Structure Rails apps with use cases, auto-registered dependencies, and Result objects. Features convention-based wiring, domain events with async subscribers, undo/rollback, ActiveRecord integration, and generators for scaffolds, use cases, and deps."
  spec.homepage    = "https://github.com/AntonioFacundo/rage_arch"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 5.2"
  spec.add_dependency "railties", ">= 5.2"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
