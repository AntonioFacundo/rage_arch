# frozen_string_literal: true

require "pathname"
require "tempfile"

RSpec.describe RageArch::DepScanner do
  let(:tmpdir) { Dir.mktmpdir }
  let(:use_cases_dir) { File.join(tmpdir, "use_cases") }

  before do
    FileUtils.mkdir_p(use_cases_dir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_use_case(path, content)
    path = File.join(use_cases_dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe "#scan" do
    it "finds constructor deps and their method calls" do
      write_use_case "process_order.rb", <<~RUBY
        class ProcessOrder < RageArch::UseCase::Base
          deps :repo, :gateway
          def call(params = {})
            repo.save(params)
            gateway.post("/orders", {})
            repo.update(1, status: "ok")
          end
        end
      RUBY
      scanner = described_class.new(use_cases_dir)
      result = scanner.scan
      expect(result[:repo].to_a.sort).to eq [:save, :update]
      expect(result[:gateway].to_a.sort).to eq [:post]
    end

    it "finds method calls without parens (e.g. service.get_all_items)" do
      write_use_case "list_items.rb", <<~RUBY
        class ListItems < RageArch::UseCase::Base
          deps :service
          def call(_params = {})
            items = service.get_all_items
            RageArch::Result.success(items)
          end
        end
      RUBY
      scanner = described_class.new(use_cases_dir)
      result = scanner.scan
      expect(result[:service].to_a).to eq [:get_all_items]
    end
  end

  describe "#methods_for" do
    it "returns method names for a symbol" do
      write_use_case "x.rb", <<~RUBY
        class X < RageArch::UseCase::Base
          deps :repo
          def call; repo.save(1); end
        end
      RUBY
      scanner = described_class.new(use_cases_dir)
      expect(scanner.methods_for(:repo).to_a).to eq [:save]
    end
  end

  describe "#folder_for" do
    it "returns the folder when the symbol is used in a use case under a subfolder" do
      write_use_case "likes/create.rb", <<~RUBY
        module Likes
          class Create < RageArch::UseCase::Base
            deps :like_store
            def call; like_store.create(user_id: 1, post_id: 2); end
          end
        end
      RUBY
      scanner = described_class.new(use_cases_dir)
      expect(scanner.folder_for(:like_store)).to eq "likes"
    end

    it "returns nil when the use case is at root (no subfolder)" do
      write_use_case "process.rb", <<~RUBY
        class Process < RageArch::UseCase::Base
          deps :repo
          def call; repo.save(1); end
        end
      RUBY
      scanner = described_class.new(use_cases_dir)
      expect(scanner.folder_for(:repo)).to be_nil
    end

    it "returns the first segment when symbol appears in nested path" do
      write_use_case "posts/comments/create.rb", <<~RUBY
        module Posts
          module Comments
            class Create < RageArch::UseCase::Base
              deps :comment_store
              def call; comment_store.save(1); end
            end
          end
        end
      RUBY
      scanner = described_class.new(use_cases_dir)
      expect(scanner.folder_for(:comment_store)).to eq "posts"
    end
  end
end
