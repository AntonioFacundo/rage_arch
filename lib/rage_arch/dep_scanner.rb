# frozen_string_literal: true

require "set"

module RageArch
  # Scans use case files to find dep symbols and the methods called on each dep.
  # Used by the rage_arch:dep generator to create stub classes with the right methods.
  # Also tracks which use case path each symbol appears in (for folder inference).
  class DepScanner
    def initialize(use_cases_root = nil)
      @use_cases_root = use_cases_root || default_use_cases_root
      @paths_for = nil
    end

    # Returns Hash symbol => Set of method names (e.g. { repo: [:save, :delete], gateway: [:get, :post] })
    def scan
      result = Hash.new { |h, k| h[k] = Set.new }
      @paths_for = Hash.new { |h, k| h[k] = Set.new }
      return result unless @use_cases_root && File.directory?(@use_cases_root)

      root = @use_cases_root.to_s
      root = root.chomp(File::SEPARATOR) + File::SEPARATOR

      Dir[File.join(@use_cases_root, "**", "*.rb")].each do |path|
        relative = path.sub(/\A#{Regexp.escape(root)}/, "")
        content = File.read(path)
        scan_file_content(content, result, relative)
      end
      result
    end

    # Returns Set of method names for the given symbol, or empty Set if unknown.
    def methods_for(symbol)
      scan[symbol.to_sym]
    end

      # Returns the folder name (first path segment) from use cases that reference this symbol,
      # e.g. "likes" when the symbol is used in app/use_cases/likes/create.rb. Returns nil if
      # no use cases reference the symbol or they are all at use_cases root.
      def folder_for(symbol)
        scan
        paths = @paths_for[symbol.to_sym]
        return nil if paths.nil? || paths.empty?

        first_path = paths.min
        seg = first_path.split(File::SEPARATOR).first
        (seg && seg != first_path) ? seg : nil
      end

    private

    def default_use_cases_root
      return nil unless defined?(Rails) && Rails.respond_to?(:root)
      Rails.root.join("app", "use_cases").to_s
    end

    def scan_file_content(content, result, relative_path = nil)
      # 1) Constructor deps: deps :repo, :gateway, :service
      constructor_symbols = content.scan(/deps\s*([^\n]+)/).flat_map do |match|
        match[0].scan(/:(\w+)/).flatten.map(&:to_sym)
      end.uniq

      constructor_symbols.each { |sym| @paths_for[sym] << relative_path } if relative_path && @paths_for

      # 2) Dynamic dep assignments: store = dep(:repo) or store = dep(:repo, default: Order)
      var_to_symbol = {}
      content.scan(/(\w+)\s*=\s*dep\s*\(\s*:(\w+)/) do |var, sym|
        var_to_symbol[var] = sym.to_sym
        @paths_for[sym.to_sym] << relative_path if relative_path && @paths_for
      end

      # 3) All symbols we care about (constructor + dynamic)
      all_symbols = (constructor_symbols + var_to_symbol.values).uniq

      # 4) Inline calls: dep(:repo).save( or dep(:repo, default: X).update(
      content.scan(/dep\s*\(\s*:(\w+)[^)]*\)\s*\.\s*(\w+)\s*[\(]/m) do |sym, method|
        result[sym.to_sym] << method.to_sym
        @paths_for[sym.to_sym] << relative_path if relative_path && @paths_for
      end

      # 5) Method calls on constructor dep (receiver name == symbol): repo.save(, gateway.get(, service.get_all_items
      #    Require a dot so we don't match "service\n  def call" as service.def
      constructor_symbols.each do |sym|
        regex = /\b#{Regexp.escape(sym.to_s)}\.\s*(\w+)\s*[\(\s]/m
        content.scan(regex) { |m| result[sym] << (m.is_a?(Array) ? m[0] : m).to_sym }
      end

      # 6) Method calls on assigned variable (require dot)
      var_to_symbol.each do |var, sym|
        regex = /\b#{Regexp.escape(var)}\.\s*(\w+)\s*[\(\s]/m
        content.scan(regex) { |m| result[sym] << (m.is_a?(Array) ? m[0] : m).to_sym }
      end
    end
  end
end
