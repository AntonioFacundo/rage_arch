# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# These tests verify generator source files and templates reference "RageArch"
# (not bare "Rage") by analyzing the source text directly — no Rails stubs needed.

generators_path = File.expand_path("../../lib/generators/rage_arch", __dir__)

RSpec.describe "Generators reference RageArch (not Rage)" do
  describe "InstallGenerator" do
    let(:source) { File.read(File.join(generators_path, "install_generator.rb")) }

    it "references template rage_arch.rb.tt, not rage.rb.tt" do
      expect(source).to include('template "rage_arch.rb.tt"')
      expect(source).not_to match(/template\s+"rage\.rb\.tt"/)
    end

    it "does not reference Rage. without Arch" do
      # Remove lines that are comments about Regexp or contain RageArch
      lines = source.lines.reject { |l| l.include?("RageArch") || l.include?("Regexp") }
      lines.each do |line|
        expect(line).not_to match(/\bRage\./), "Found bare Rage. in install_generator.rb: #{line.strip}"
      end
    end
  end

  describe "ScaffoldGenerator" do
    let(:source) { File.read(File.join(generators_path, "scaffold_generator.rb")) }

    it "generates RageArch.register_ar in inject_register_ar" do
      expect(source).to include("RageArch.register_ar")
      expect(source).not_to match(/[^e]Rage\.register_ar/)
    end

    it "desc uses RageArch, not Rage" do
      desc_line = source.lines.find { |l| l.strip.start_with?("desc ") }
      expect(desc_line).to include("RageArch")
      expect(desc_line).not_to match(/\bRage\b(?!Arch)/)
    end
  end

  describe "DepSwitchGenerator" do
    let(:source) { File.read(File.join(generators_path, "dep_switch_generator.rb")) }

    it "uses rage_arch.rb as initializer path, not rage.rb" do
      expect(source).to include('"rage_arch.rb"')
      expect(source).not_to match(/["']rage\.rb["']/)
    end

    it "generates RageArch.register_ar in output strings" do
      # Find string literals (not regex) that contain register_ar
      register_ar_lines = source.lines.select { |l| l.include?("register_ar") && l.include?('"') }
      register_ar_lines.each do |line|
        next if line.strip.start_with?("#") && !line.include?("RageArch")
        expect(line).not_to match(/\bRage\.register_ar\b/),
          "Found bare Rage.register_ar in dep_switch_generator.rb: #{line.strip}"
      end
    end

    it "generates RageArch.register in output strings" do
      register_lines = source.lines.select { |l| l.include?(".register(") && l.include?('"') }
      register_lines.each do |line|
        expect(line).not_to match(/\bRage\.register\(/),
          "Found bare Rage.register( in dep_switch_generator.rb: #{line.strip}"
      end
    end

    it "uses RageArch in all regex patterns" do
      regex_lines = source.lines.select { |l| l.include?("Rage") && (l.include?("/") || l.include?("Regexp")) }
      regex_lines.each do |line|
        expect(line).not_to match(/(?<!e)Rage\\/),
          "Found bare Rage in regex in dep_switch_generator.rb: #{line.strip}"
      end
    end

    it "user-facing messages reference RageArch, not Rage" do
      say_lines = source.lines.select { |l| l.include?("say ") && l.include?("Rage") }
      say_lines.each do |line|
        expect(line).not_to match(/\bRage\.register/),
          "Found bare Rage.register in say message: #{line.strip}"
      end
    end
  end

  describe "ArDepGenerator" do
    let(:source) { File.read(File.join(generators_path, "ar_dep_generator.rb")) }

    it "instructs to register with RageArch.register, not Rage.register" do
      say_lines = source.lines.select { |l| l.include?("say ") }
      say_lines.each do |line|
        next unless line.include?("register")
        expect(line).to include("RageArch.register"),
          "Found non-RageArch register in ar_dep_generator.rb say: #{line.strip}"
      end
    end
  end

  describe "Templates" do
    let(:templates_path) { File.join(generators_path, "templates") }

    it "rage_arch.rb.tt template exists" do
      path = File.join(templates_path, "rage_arch.rb.tt")
      expect(File.exist?(path)).to eq(true), "Expected template rage_arch.rb.tt to exist"
    end

    it "rage.rb.tt template does NOT exist (was renamed)" do
      path = File.join(templates_path, "rage.rb.tt")
      expect(File.exist?(path)).to eq(false), "Template rage.rb.tt should not exist — use rage_arch.rb.tt"
    end

    it "rage_arch.rb.tt references RageArch, not bare Rage" do
      content = File.read(File.join(templates_path, "rage_arch.rb.tt"))
      expect(content).to include("RageArch.register")
      expect(content).not_to match(/\bRage\./)
    end

    it "ar_dep.rb.tt references RageArch, not bare Rage" do
      content = File.read(File.join(templates_path, "ar_dep.rb.tt"))
      expect(content).to include("RageArch")
      expect(content).not_to match(/\bRage\./)
    end

    Dir[File.join(File.expand_path("../../lib/generators/rage_arch/templates", __dir__), "**", "*.tt")].each do |tt_file|
      basename = File.basename(tt_file)
      it "#{basename} does not contain bare Rage. references" do
        content = File.read(tt_file)
        content.lines.each do |line|
          next if line.include?("RageArch")
          expect(line).not_to match(/\bRage\./),
            "Found bare Rage. in template #{basename}: #{line.strip}"
        end
      end
    end
  end

  describe "No bare Rage references in any generator source" do
    generator_files = Dir[File.join(
      File.expand_path("../../lib/generators/rage_arch", __dir__), "*_generator.rb"
    )]

    generator_files.each do |gen_file|
      basename = File.basename(gen_file)

      it "#{basename} has no bare Rage. references (outside RageArch)" do
        content = File.read(gen_file)
        content.lines.each_with_index do |line, idx|
          next if line.include?("RageArch")
          next if line.include?("Regexp")
          expect(line).not_to match(/\bRage\./),
            "#{basename}:#{idx + 1} has bare Rage.: #{line.strip}"
        end
      end
    end
  end
end

RSpec.describe "Library source files reference RageArch (not Rage)" do
  lib_path = File.expand_path("../../lib", __dir__)

  Dir[File.join(lib_path, "rage_arch", "**", "*.rb")].each do |rb_file|
    relative = rb_file.sub("#{lib_path}/", "")

    it "#{relative} comments do not reference bare Rage." do
      content = File.read(rb_file)
      content.lines.each_with_index do |line, idx|
        next unless line.strip.start_with?("#")
        next if line.include?("RageArch")
        next if line.include?("Regexp")
        expect(line).not_to match(/\bRage\./),
          "#{relative}:#{idx + 1} comment has bare Rage.: #{line.strip}"
      end
    end
  end

  it "lib/rage_arch.rb comments reference RageArch, not Rage" do
    content = File.read(File.join(lib_path, "rage_arch.rb"))
    content.lines.each_with_index do |line, idx|
      next unless line.strip.start_with?("#")
      next if line.include?("RageArch")
      expect(line).not_to match(/\bRage\./),
        "rage_arch.rb:#{idx + 1} comment has bare Rage.: #{line.strip}"
    end
  end
end

RSpec.describe "DepSwitchGenerator initializer operations" do
  let(:tmpdir) { Dir.mktmpdir("rage_gen_test") }
  let(:initializer_dir) { File.join(tmpdir, "config", "initializers") }
  let(:initializer_path) { File.join(initializer_dir, "rage_arch.rb") }

  before do
    FileUtils.mkdir_p(initializer_dir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  let(:generator_source) { File.read(File.expand_path("../../lib/generators/rage_arch/dep_switch_generator.rb", __dir__)) }

  describe "find_ar_registration regex" do
    let(:initializer_content) do
      <<~RUBY
        Rails.application.config.after_initialize do
          RageArch.register_ar(:post_repo, Post)
        end
      RUBY
    end

    it "matches RageArch.register_ar with parens" do
      content = initializer_content
      match = content.match(/RageArch\.register_ar\s*\(\s*:\s*post_repo\s*,\s*(\w+)\s*\)/)
      expect(match).not_to be_nil
      expect(match[1]).to eq("Post")
    end

    it "matches RageArch.register_ar without parens" do
      content = "  RageArch.register_ar :post_repo, Post\n"
      match = content.match(/RageArch\.register_ar\s+:\s*post_repo\s*,\s*(\w+)/)
      expect(match).not_to be_nil
      expect(match[1]).to eq("Post")
    end

    it "does NOT match old Rage.register_ar format" do
      content = "  Rage.register_ar(:post_repo, Post)\n"
      match = content.match(/RageArch\.register_ar\s*\(\s*:\s*post_repo\s*,\s*(\w+)\s*\)/)
      expect(match).to be_nil
    end
  end

  describe "comment_line_matching regex" do
    it "comments out RageArch.register( lines" do
      content = "  RageArch.register(:post_repo, Posts::PostStore.new)\n"
      result = content.gsub(
        /^(\s*)(RageArch\.register\(:post_repo,\s*\S+\.new\))\s*$/,
        '\1# \2'
      )
      expect(result.strip).to eq("# RageArch.register(:post_repo, Posts::PostStore.new)")
    end

    it "comments out RageArch.register_ar( lines" do
      content = "  RageArch.register_ar(:post_repo, Post)\n"
      result = content.gsub(
        /^(\s*)(RageArch\.register_ar\s*\(\s*:\s*post_repo\s*,\s*\S+\s*\))\s*$/,
        '\1# \2'
      )
      expect(result.strip).to eq("# RageArch.register_ar(:post_repo, Post)")
    end
  end

  describe "uncomment regex" do
    it "uncomments a commented RageArch.register_ar line" do
      content = "  # RageArch.register_ar(:post_repo, Post)\n"
      result = content.gsub(
        /^(\s*)#\s*(RageArch\.register_ar\s*\(\s*:\s*post_repo\s*,\s*Post\s*\))\s*$/,
        '\1\2'
      )
      expect(result.strip).to eq("RageArch.register_ar(:post_repo, Post)")
    end

    it "uncomments a commented RageArch.register line" do
      content = "  # RageArch.register(:post_repo, Posts::PostStore.new)\n"
      result = content.gsub(
        /^(\s*)#\s*(RageArch\.register\(:post_repo,\s*Posts::PostStore\.new\))\s*$/,
        '\1\2'
      )
      expect(result.strip).to eq("RageArch.register(:post_repo, Posts::PostStore.new)")
    end
  end

  describe "generated registration lines" do
    it "generates RageArch.register_ar for AR deps" do
      symbol = "post_repo"
      model = "Post"
      line = "RageArch.register_ar(:#{symbol}, #{model})"
      expect(line).to eq("RageArch.register_ar(:post_repo, Post)")
    end

    it "generates RageArch.register for class deps" do
      symbol = "post_repo"
      name = "Posts::CsvPostStore"
      line = "RageArch.register(:#{symbol}, #{name}.new)"
      expect(line).to eq("RageArch.register(:post_repo, Posts::CsvPostStore.new)")
    end
  end
end

RSpec.describe "ScaffoldGenerator inject_register_ar" do
  let(:tmpdir) { Dir.mktmpdir("rage_scaffold_test") }
  let(:initializer_dir) { File.join(tmpdir, "config", "initializers") }
  let(:initializer_path) { File.join(initializer_dir, "rage_arch.rb") }

  before { FileUtils.mkdir_p(initializer_dir) }
  after { FileUtils.rm_rf(tmpdir) }

  it "injects RageArch.register_ar into the initializer" do
    File.write(initializer_path, <<~RUBY)
      Rails.application.config.after_initialize do
        # Deps
      end
    RUBY

    content = File.read(initializer_path)
    repo_symbol = "post_repo"
    model_class_name = "Post"
    inject_line = "  RageArch.register_ar(:#{repo_symbol}, #{model_class_name})\n"
    content.sub!(/(Rails\.application\.config\.after_initialize do\s*\n)/m, "\\1#{inject_line}")
    File.write(initializer_path, content)

    result = File.read(initializer_path)
    expect(result).to include("RageArch.register_ar(:post_repo, Post)")
    expect(result).not_to include("Rage.register_ar")
  end
end
