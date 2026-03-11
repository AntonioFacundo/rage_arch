# frozen_string_literal: true

require "rails/generators/named_base"

module RageArch
  module Generators
    class UseCaseGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Create a use case in app/use_cases/."
      def create_use_case
        template "use_case.rb.tt", File.join("app/use_cases", *class_path, "#{file_name}.rb")
      end

      def class_name_without_module
        file_name.camelize
      end

      def symbol_name
        file_name
      end

      def use_case_symbol
        ":#{symbol_name}"
      end

      def module_namespace
        return "" if class_path.empty?
        class_path.map(&:camelize).join("::") + "::"
      end
    end
  end
end
