# frozen_string_literal: true

require "rails/generators/base"

module RageArch
  module Generators
    class DepSwitchGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :symbol_arg, type: :string, required: true, banner: "SYMBOL"
      argument :class_name_arg, type: :string, optional: true, banner: "[CLASS_NAME]",
        default: nil

      desc "List implementations for a dep symbol and set which one is active in config/initializers/rage_arch.rb"
      def switch_dep
        symbol = symbol_name
        options = build_options(symbol)
        if options.empty?
          say "No implementations found for :#{symbol}.", :red
          say "Create a dep with: rails g rage_arch:dep #{symbol} [ClassName]"
          say "Or add RageArch.register_ar(:#{symbol}, Model) in config/initializers/rage_arch.rb", :red
          return
        end
        chosen = if class_name_arg.present?
          resolve_requested(symbol, class_name_arg, options)
        elsif options.size == 1
          options.first
        else
          ask_choice(symbol, options)
        end
        return unless chosen

        update_initializer(symbol, chosen)
        msg = chosen[:type] == :ar ?
          "Registered :#{symbol} -> Active Record (#{chosen[:model]}) in config/initializers/rage_arch.rb" :
          "Registered :#{symbol} -> #{chosen[:name]}.new in config/initializers/rage_arch.rb"
        say msg, :green
      end

      def symbol_name
        symbol_arg.to_s.underscore
      end

      private

      def deps_path
        File.join(destination_root, "app", "deps")
      end

      def initializer_path
        File.join(destination_root, "config", "initializers", "rage_arch.rb")
      end

      def find_ar_registration(symbol)
        path = initializer_path
        return nil unless File.exist?(path)
        content = File.read(path)
        # Match active or commented: RageArch.register_ar(:post_store, Post) or RageArch.register_ar :post_store, Post
        content.each_line do |line|
          stripped = line.strip
          next if stripped.start_with?("#")
          if stripped =~ /RageArch\.register_ar\s*\(\s*:\s*#{Regexp.escape(symbol)}\s*,\s*(\w+)\s*\)/ ||
             stripped =~ /RageArch\.register_ar\s+:\s*#{Regexp.escape(symbol)}\s*,\s*(\w+)/
            return $1
          end
        end
        # Also check commented lines so "default" stays as option after switching away
        content.each_line do |line|
          stripped = line.strip.delete_prefix("#").strip
          next if stripped.empty?
          if stripped =~ /RageArch\.register_ar\s*\(\s*:\s*#{Regexp.escape(symbol)}\s*,\s*(\w+)\s*\)/ ||
             stripped =~ /RageArch\.register_ar\s+:\s*#{Regexp.escape(symbol)}\s*,\s*(\w+)/
            return $1
          end
        end
        nil
      end

      def find_dep_classes(symbol)
        return [] unless File.directory?(deps_path)

        Dir[File.join(deps_path, "**", "*.rb")].filter_map do |path|
          base = File.basename(path, ".rb")
          # symbol.rb, symbol_suffix.rb (e.g. post_store_mysql), or prefix_symbol.rb (e.g. mysql_post_store)
          next unless base == symbol || base.start_with?("#{symbol}_") || base.end_with?("_#{symbol}")
          path_to_class_name(path)
        end.sort
      end

      # Derives full constant from path (Zeitwerk convention):
      # app/deps/posts/post_store.rb → Posts::PostStore
      # app/deps/post_store.rb (flat, legacy) → PostStore
      def path_to_class_name(path)
        base = File.join(destination_root, "app", "deps")
        relative = path.sub(/\A#{Regexp.escape(base + File::SEPARATOR)}/, "").sub(/\.rb\z/, "")
        parts = relative.split(File::SEPARATOR).map(&:camelize)
        if parts.size > 1
          parts.join("::")
        else
          parts.first
        end
      end

      def build_options(symbol)
        options = []
        ar_model = find_ar_registration(symbol)
        options << { type: :ar, model: ar_model } if ar_model
        find_dep_classes(symbol).each { |name| options << { type: :class, name: name } }
        options
      end

      def display_option(opt)
        opt[:type] == :ar ? "Active Record (#{opt[:model]})" : opt[:name]
      end

      def resolve_requested(symbol, requested, options)
        raw = requested.to_s.strip
        return nil if raw.empty?
        normalized = raw.camelize
        # Allow "ar" or "activerecord" (any case) to select Active Record default
        if raw.downcase == "ar" || raw.downcase == "activerecord"
          opt = options.find { |o| o[:type] == :ar }
          unless opt
            say "No Active Record registration found for :#{symbol}. Available: #{options.map { |o| display_option(o) }.join(', ')}", :red
            return nil
          end
          return opt
        end
        opt = options.find { |o| o[:type] == :class && (o[:name] == normalized || o[:name].end_with?("::#{normalized}")) }
        unless opt
          say "Unknown implementation '#{requested}' for :#{symbol}. Available: #{options.map { |o| display_option(o) }.join(', ')}", :red
          return nil
        end
        opt
      end

      def ask_choice(symbol, options)
        say "Implementations for :#{symbol}:", :green
        options.each_with_index do |opt, i|
          say "  #{i + 1}. #{display_option(opt)}"
        end
        choice = ask("\nWhich one to activate? [1-#{options.size}]: ", :green)
        idx = choice.to_i
        unless idx.between?(1, options.size)
          say "Invalid choice.", :red
          return nil
        end
        options[idx - 1]
      end

      def update_initializer(symbol, option)
        path = initializer_path
        unless File.exist?(path)
          say "config/initializers/rage_arch.rb not found.", :red
          return
        end
        content = File.read(path)
        # Comment out every active registration for this symbol (do not remove)
        content = comment_line_matching(content, symbol, :register)
        content = comment_line_matching(content, symbol, :register_ar)
        # Uncomment or add the chosen registration
        chosen_line = option[:type] == :ar ?
          "RageArch.register_ar(:#{symbol}, #{option[:model]})" :
          "RageArch.register(:#{symbol}, #{option[:name]}.new)"
        content = uncomment_or_add(content, symbol, option, chosen_line)
        File.write(path, content)
      end

      def comment_line_matching(content, symbol, form)
        if form == :register
          content.gsub(/^(\s*)(RageArch\.register\(:#{Regexp.escape(symbol)},\s*\S+\.new\))\s*$/, '\1# \2')
        else
          # register_ar with parens or with space
          content
            .gsub(/^(\s*)(RageArch\.register_ar\s*\(\s*:\s*#{Regexp.escape(symbol)}\s*,\s*\S+\s*\))\s*$/, '\1# \2')
            .gsub(/^(\s*)(RageArch\.register_ar\s+:\s*#{Regexp.escape(symbol)}\s*,\s*\S+)\s*$/, '\1# \2')
        end
      end

      def uncomment_or_add(content, symbol, option, chosen_line)
        if option[:type] == :ar
          model = option[:model]
          # Uncomment if there is a commented register_ar line for this symbol and model
          content = content.gsub(
            /^(\s*)#\s*(RageArch\.register_ar\s*\(\s*:\s*#{Regexp.escape(symbol)}\s*,\s*#{Regexp.escape(model)}\s*\))\s*$/,
            '\1\2'
          )
          content = content.gsub(
            /^(\s*)#\s*(RageArch\.register_ar\s+:\s*#{Regexp.escape(symbol)}\s*,\s*#{Regexp.escape(model)})\s*$/,
            '\1\2'
          )
        else
          class_name = option[:name]
          # Uncomment if there is a commented RageArch.register line for this symbol and class
          content = content.gsub(
            /^(\s*)#\s*(RageArch\.register\(:#{Regexp.escape(symbol)},\s*#{Regexp.escape(class_name)}\.new\))\s*$/,
            '\1\2'
          )
        end
        # If chosen line is still not present as active, add it inside after_initialize
        return content if chosen_already_active?(content, symbol, option, chosen_line)

        if content =~ /Rails\.application\.config\.after_initialize\s+do/
          content = content.sub(/(Rails\.application\.config\.after_initialize\s+do)\n/, "\\1\n  #{chosen_line}\n")
        else
          content = content.rstrip + "\n\nRails.application.config.after_initialize do\n  #{chosen_line}\nend\n"
        end
        content
      end

      def chosen_already_active?(content, symbol, option, chosen_line)
        content.lines.any? do |line|
          next false if line.lstrip.start_with?("#")
          if option[:type] == :ar
            model = option[:model]
            line.include?("register_ar") && line.include?(":#{symbol}") && line.include?(model.to_s)
          else
            line.include?(chosen_line)
          end
        end
      end
    end
  end
end