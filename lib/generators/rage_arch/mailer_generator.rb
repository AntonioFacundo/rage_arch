# frozen_string_literal: true

require "rails/generators/base"

module RageArch
  module Generators
    class MailerGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :actions, type: :array, default: [], banner: "action action"

      desc "Generate a Rails mailer and a RageArch dep wrapper (auto-registered from app/deps/)."
      def create_rails_mailer
        args = [name] + actions
        invoke "mailer", args
      end

      def create_dep
        dep_dir = File.join("app/deps")
        template "mailer/mailer_dep.rb.tt", File.join(dep_dir, "#{dep_file_name}.rb")
      end

      private

      def mailer_class_name
        name.camelize
      end

      def dep_class_name
        "#{mailer_class_name}Dep"
      end

      def dep_file_name
        "#{file_name}_dep"
      end

      def dep_symbol
        file_name.underscore
      end
    end
  end
end
