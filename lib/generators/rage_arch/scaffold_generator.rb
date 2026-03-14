# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module RageArch
  module Generators
    class ScaffoldGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field:type field:type"
      class_option :skip_model, type: :boolean, default: false, desc: "Skip model and migration (use when model already exists)"
      class_option :api, type: :boolean, default: false, desc: "Generate API-only controller (JSON responses, no views)"

      desc "Generate a full RageArch CRUD: model, migration, use cases (list/show/create/update/destroy), dep (AR), controller, and routes. With --api: JSON responses only, no views."
      def create_all
        create_model_and_migration
        create_use_cases
        create_dep
        invoke_rails_scaffold_views
        create_controller
        add_route
        inject_register_ar
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
        template "scaffold/list.rb.tt",   File.join(dir, "list.rb")
        template "scaffold/show.rb.tt",   File.join(dir, "show.rb")
        template "scaffold/new.rb.tt",    File.join(dir, "new.rb")
        template "scaffold/create.rb.tt", File.join(dir, "create.rb")
        template "scaffold/update.rb.tt", File.join(dir, "update.rb")
        template "scaffold/destroy.rb.tt", File.join(dir, "destroy.rb")
      end

      def create_dep
        dep_dir = File.join("app/deps", plural_name)
        empty_directory dep_dir
        template "scaffold/post_repo.rb.tt", File.join(dep_dir, "#{singular_name}_repo.rb")
      end

      def create_controller
        template_name = options[:api] ? "scaffold/api_controller.rb.tt" : "scaffold/controller.rb.tt"
        template template_name, File.join("app/controllers", "#{plural_name}_controller.rb"), force: true
      end

      # Reuse Rails' scaffold_controller: with --api it generates API controller (no views); otherwise controller + views.
      def invoke_rails_scaffold_views
        args = [name] + attributes.map(&:to_s)
        opts = { skip_routes: true }
        opts[:api] = true if options[:api]
        invoke "scaffold_controller", args, opts
      end

      def add_route
        route "resources :#{plural_name}"
      end

      def inject_register_ar
        initializer_path = File.join(destination_root, "config/initializers/rage_arch.rb")
        return unless File.exist?(initializer_path)
        content = File.read(initializer_path)
        return if content.include?("register_ar(:#{repo_symbol})")
        inject_line = "  RageArch.register_ar(:#{repo_symbol}, #{model_class_name})\n"
        content.sub!(/(Rails\.application\.config\.after_initialize do\s*\n)/m, "\\1#{inject_line}")
        File.write(initializer_path, content)
        say_status :inject, "config/initializers/rage_arch.rb (register_ar :#{repo_symbol})", :green
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
