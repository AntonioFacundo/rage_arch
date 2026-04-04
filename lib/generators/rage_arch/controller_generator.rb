# frozen_string_literal: true

require "rails/generators/base"

module RageArch
  module Generators
    class ControllerGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :actions, type: :array, default: [], banner: "action action"

      desc "Generate a thin RageArch controller with use cases for each action."
      def create_controller
        template "controller/controller.rb.tt", File.join("app/controllers", "#{plural_file_name}_controller.rb")
      end

      def create_use_cases
        actions.each do |action|
          @current_action = action
          template "controller/action_use_case.rb.tt", File.join("app/use_cases", plural_file_name, "#{action}.rb")
        end
      end

      def add_routes
        return if actions.empty?
        lines = actions.map { |a| "  get \"#{plural_file_name}/#{a}\", to: \"#{plural_file_name}##{a}\"" }
        route lines.join("\n")
      end

      private

      def plural_file_name
        file_name.pluralize
      end

      def controller_class_name
        plural_file_name.camelize
      end

      def module_name
        plural_file_name.camelize
      end

      def current_action
        @current_action
      end

      def use_case_symbol(action)
        "#{plural_file_name}_#{action}"
      end
    end
  end
end
