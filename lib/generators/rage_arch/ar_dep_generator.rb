# frozen_string_literal: true

require "rails/generators/base"
require "rage_arch/dep_scanner"

module RageArch
  module Generators
    class ArDepGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :symbol_arg, type: :string, required: true, banner: "SYMBOL"
      argument :model_arg, type: :string, required: true, banner: "MODEL"

      desc "Create a dep class that wraps an Active Record model (build, find, save, update, destroy, list). Scans use cases for extra method calls and adds stubs for them. Example: rails g rage_arch:ar_dep post_store Post"
      def create_ar_dep
        @extra_methods = extra_methods
        template "ar_dep.rb.tt", File.join("app/deps", module_dir, "#{dep_file_name}.rb")
        say "Register in config/initializers/rage_arch.rb: RageArch.register(:#{symbol_name}, #{full_class_name}.new)", :green
      end

      STANDARD_AR_METHODS = %i[build find save update destroy list].freeze

      # Methods that use cases call on this dep but are not in the standard AR adapter
      def extra_methods
        detected = scanner.methods_for(symbol_name).to_a
        (detected - STANDARD_AR_METHODS).sort
      end

      def symbol_name
        symbol_arg.to_s.underscore
      end

      def model_name
        model_arg.camelize
      end

      def module_dir
        inferred_module_dir || use_case_folder
      end

      def module_name
        module_dir.camelize
      end

      def use_case_folder
        scanner.folder_for(symbol_name)
      end

      def inferred_module_dir
        entity = symbol_name.split("_").first
        entity.pluralize
      end

      def dep_file_name
        symbol_name
      end

      def class_name
        symbol_name.camelize
      end

      def full_class_name
        "#{module_name}::#{class_name}"
      end

      def scanner
        @scanner ||= begin
          root = destination_root
          RageArch::DepScanner.new(File.join(root, "app", "use_cases")).tap(&:scan)
        end
      end
    end
  end
end
