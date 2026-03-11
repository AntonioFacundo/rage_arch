# frozen_string_literal: true

require "rails/generators/base"
require "rage_arch/dep_scanner"

module RageArch
  module Generators
    class DepGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :symbol_arg, type: :string, required: true, banner: "SYMBOL"
      argument :class_name_arg, type: :string, optional: true, banner: "[CLASS_NAME]",
        default: nil

      desc "Create a dep class in app/deps/, grouped by folder. The folder is inferred from the symbol first (post_store → posts, like_store → likes). If the symbol has no clear entity, the folder is taken from use cases that reference it. Optional CLASS_NAME is the generated class (e.g. CsvPostStore); default is SYMBOL.camelize. If the file already exists, only adds stub methods that are missing (detected from use cases but not yet in the class)."
      def create_dep
        @methods = detected_methods
        if @methods.empty?
          say "No method calls found for dep :#{symbol_name} in app/use_cases/. Creating with a single stub.", :yellow
          @methods = [:call]
        end
        target_path = File.join("app/deps", module_dir, "#{dep_file_name}.rb")
        if File.exist?(File.join(destination_root, target_path))
          add_missing_methods_only(target_path)
        else
          template "dep.rb.tt", target_path
        end
      end

      # When the dep file already exists, parse it for existing method names and insert only stubs for missing ones.
      def add_missing_methods_only(relative_path)
        full_path = File.join(destination_root, relative_path)
        content = File.read(full_path)
        existing = content.scan(/^\s+def\s+(\w+)\s*[\(\s]/m).flatten.uniq.map(&:to_sym)
        missing = @methods - existing
        if missing.empty?
          say "All detected methods already present in #{relative_path}.", :green
          return
        end
        indent = content[/^(\s+)def\s+\w+/m, 1] || "  "
        stubs = missing.map { |m| method_stub(m, indent) }.join("\n")
        # Insert before the class's closing end (last indented "end" before the file's final "end").
        lines = content.lines
        insert_at = lines.length - 1
        insert_at -= 1 while insert_at >= 0 && lines[insert_at] =~ /^\s*$/
        insert_at -= 1 while insert_at > 0 && lines[insert_at] !~ /^\s+end\s*$/
        new_content = lines[0...insert_at].join + "\n#{stubs}\n" + lines[insert_at..].join
        File.write(full_path, new_content)
        say "Added #{missing.size} method(s) to #{relative_path}: #{missing.map(&:to_s).join(', ')}", :green
      end

      def method_stub(method_name, indent = "  ")
        body_indent = indent + "  "
        <<~RUBY.strip
          #{indent}def #{method_name}(*args, **kwargs)
          #{body_indent}# TODO: implement
          #{body_indent}raise NotImplementedError, "#{full_class_name}##{method_name}"
          #{indent}end
        RUBY
      end

      def symbol_name
        symbol_arg.to_s.underscore
      end

      # Folder from use cases that reference this symbol (e.g. likes/create.rb → "likes"), or inferred from symbol.
      # Prefer inferred from symbol (post_store → posts) so the dep lives with its domain, not only where it's referenced.
      def module_dir
        inferred_module_dir || use_case_folder
      end

      # Module name for the class (e.g. Likes, Posts). Matches Zeitwerk: app/deps/likes/ → Likes::
      def module_name
        module_dir.camelize
      end

      # When use cases in app/use_cases/likes/*.rb reference this symbol, returns "likes"
      def use_case_folder
        scanner.folder_for(symbol_name)
      end

      # Fallback when no use case references the symbol: like_store → "likes", post_store → "posts"
      def inferred_module_dir
        entity = symbol_name.split("_").first
        entity.pluralize
      end

      def class_name
        if class_name_arg.present?
          class_name_arg.camelize
        else
          symbol_name.camelize
        end
      end

      def dep_file_name
        if class_name_arg.present?
          class_name_arg.underscore
        else
          symbol_name
        end
      end

      def full_class_name
        "#{module_name}::#{class_name}"
      end

      def detected_methods
        scanner.methods_for(symbol_name).to_a.sort
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
