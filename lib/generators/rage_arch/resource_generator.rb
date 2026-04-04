# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module RageArch
  module Generators
    class ResourceGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field:type field:type"
      class_option :skip_model, type: :boolean, default: false, desc: "Skip model and migration (use when model already exists)"

      desc "Generate a RageArch resource: model, migration, CRUD use cases, dep, API-style controller, and routes (no views)."
      def create_all
        create_model_and_migration
        create_use_cases
        create_dep
        create_controller
        add_route
      end

      private

      def create_model_and_migration
        return if options[:skip_model]
        args = [name] + attributes.map(&:to_s)
        invoke "active_record:model", args
      end

      def create_use_cases
        dir = File.join("app/use_cases", plural_name)
        empty_directory dir
        template "scaffold/list.rb.tt",    File.join(dir, "list.rb")
        template "scaffold/show.rb.tt",    File.join(dir, "show.rb")
        template "scaffold/new.rb.tt",     File.join(dir, "new.rb")
        template "scaffold/create.rb.tt",  File.join(dir, "create.rb")
        template "scaffold/update.rb.tt",  File.join(dir, "update.rb")
        template "scaffold/destroy.rb.tt", File.join(dir, "destroy.rb")
      end

      def create_dep
        dep_dir = File.join("app/deps", plural_name)
        empty_directory dep_dir
        template "scaffold/post_repo.rb.tt", File.join(dep_dir, "#{singular_name}_repo.rb")
      end

      def create_controller
        template "scaffold/api_controller.rb.tt", File.join("app/controllers", "#{plural_name}_controller.rb")
      end

      def add_route
        route "resources :#{plural_name}"
      end

      def plural_name
        name.underscore.pluralize
      end

      def singular_name
        name.underscore
      end

      def model_class_name
        name.camelize
      end

      def module_name
        plural_name.camelize
      end

      def repo_symbol
        "#{singular_name}_repo"
      end

      def repo_class_name
        "#{module_name}::#{singular_name.camelize}Repo"
      end

      def list_symbol
        "#{plural_name}_list"
      end

      def show_symbol
        "#{plural_name}_show"
      end

      def create_symbol
        "#{plural_name}_create"
      end

      def update_symbol
        "#{plural_name}_update"
      end

      def destroy_symbol
        "#{plural_name}_destroy"
      end

      def new_symbol
        "#{plural_name}_new"
      end

      def attribute_names_for_permit
        return [] if attributes.blank?
        attributes.map { |a| a.to_s.split(":").first.to_sym }
      end
    end
  end
end
