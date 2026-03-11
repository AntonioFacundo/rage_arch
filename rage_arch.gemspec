# frozen_string_literal: true

require_relative "lib/rage_arch/version"

Gem::Specification.new do |spec|
  spec.name    = "rage_arch"
  spec.version = RageArch::VERSION
  spec.authors = ["Rage Corp"]
  spec.email   = [""]

  spec.summary     = "Clean Architecture Light for Rails: use cases, injectable deps, Result."
  spec.description = "Gem to structure Rails apps with use cases, dependencies injectable by symbol, and Result object (success/failure). Includes container, use case base, and rails g rage_arch:use_case generator."
  spec.homepage    = "https://github.com/rage-corp/rage_arch"
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
