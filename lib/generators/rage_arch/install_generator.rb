# frozen_string_literal: true

require "rails/generators/base"

module RageArch
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Create config/initializers/rage_arch.rb, app/use_cases, app/deps, and include RageArch::Controller in ApplicationController"
      def install
        create_initializer
        create_directories
        inject_controller
      end

      private

      def create_initializer
        path = "config/initializers/rage_arch.rb"
        full_path = File.join(destination_root, path)
        if File.exist?(full_path)
          say_status :skip, path, :yellow
          return
        end
        template "rage.rb.tt", path
      end

      def create_directories
        %w[app/use_cases app/deps].each do |dir|
          full_path = File.join(destination_root, dir)
          if File.directory?(full_path)
            say_status :skip, dir, :yellow
            next
          end
          empty_directory dir
          create_file File.join(dir, ".keep"), ""
        end
      end

      def inject_controller
        path = "app/controllers/application_controller.rb"
        full_path = File.join(destination_root, path)
        unless File.exist?(full_path)
          say_status :skip, path, :yellow
          return
        end
        content = File.read(full_path)
        if content.include?("RageArch::Controller")
          say_status :skip, path, :yellow
          return
        end
        injection = "  include RageArch::Controller\n"
        if content =~ /(class\s+ApplicationController\s*<\s*\S+)/
          content.sub!(Regexp.last_match(0), "#{Regexp.last_match(0)}\n#{injection.chomp}")
          File.write(full_path, content)
          say_status :inject, path, :green
        else
          say_status :skip, path, :yellow
        end
      end
    end
  end
end
