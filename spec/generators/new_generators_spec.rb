# frozen_string_literal: true

require "spec_helper"

generators_path = File.expand_path("../../lib/generators/rage_arch", __dir__)
templates_path = File.join(generators_path, "templates")

RSpec.describe "ControllerGenerator" do
  let(:source) { File.read(File.join(generators_path, "controller_generator.rb")) }

  it "exists" do
    expect(File.exist?(File.join(generators_path, "controller_generator.rb"))).to eq(true)
  end

  it "has no bare Rage. references" do
    source.lines.each_with_index do |line, idx|
      next if line.include?("RageArch")
      expect(line).not_to match(/\bRage\./),
        "controller_generator.rb:#{idx + 1} has bare Rage.: #{line.strip}"
    end
  end

  describe "templates" do
    it "controller template exists" do
      expect(File.exist?(File.join(templates_path, "controller", "controller.rb.tt"))).to eq(true)
    end

    it "action use case template exists" do
      expect(File.exist?(File.join(templates_path, "controller", "action_use_case.rb.tt"))).to eq(true)
    end

    it "controller template uses run with symbol" do
      content = File.read(File.join(templates_path, "controller", "controller.rb.tt"))
      expect(content).to include("run :")
    end

    it "action use case template inherits from RageArch::UseCase::Base" do
      content = File.read(File.join(templates_path, "controller", "action_use_case.rb.tt"))
      expect(content).to include("RageArch::UseCase::Base")
    end

    it "action use case template has no bare Rage. references" do
      content = File.read(File.join(templates_path, "controller", "action_use_case.rb.tt"))
      content.lines.each do |line|
        next if line.include?("RageArch")
        expect(line).not_to match(/\bRage\./),
          "action_use_case.rb.tt has bare Rage.: #{line.strip}"
      end
    end
  end
end

RSpec.describe "ResourceGenerator" do
  let(:source) { File.read(File.join(generators_path, "resource_generator.rb")) }

  it "exists" do
    expect(File.exist?(File.join(generators_path, "resource_generator.rb"))).to eq(true)
  end

  it "has no bare Rage. references" do
    source.lines.each_with_index do |line, idx|
      next if line.include?("RageArch")
      expect(line).not_to match(/\bRage\./),
        "resource_generator.rb:#{idx + 1} has bare Rage.: #{line.strip}"
    end
  end

  it "reuses scaffold templates (no views)" do
    expect(source).to include("scaffold/list.rb.tt")
    expect(source).to include("scaffold/api_controller.rb.tt")
  end

  it "does not invoke scaffold_controller (no views)" do
    expect(source).not_to include("scaffold_controller")
    expect(source).not_to include("invoke_rails_scaffold_views")
  end

  it "has --skip-model option" do
    expect(source).to include("skip_model")
  end
end

RSpec.describe "MailerGenerator" do
  let(:source) { File.read(File.join(generators_path, "mailer_generator.rb")) }

  it "exists" do
    expect(File.exist?(File.join(generators_path, "mailer_generator.rb"))).to eq(true)
  end

  it "has no bare Rage. references" do
    source.lines.each_with_index do |line, idx|
      next if line.include?("RageArch")
      expect(line).not_to match(/\bRage\./),
        "mailer_generator.rb:#{idx + 1} has bare Rage.: #{line.strip}"
    end
  end

  it "invokes the Rails mailer generator" do
    expect(source).to include('invoke "mailer"')
  end

  describe "templates" do
    it "mailer dep template exists" do
      expect(File.exist?(File.join(templates_path, "mailer", "mailer_dep.rb.tt"))).to eq(true)
    end

    it "mailer dep template uses deliver_later" do
      content = File.read(File.join(templates_path, "mailer", "mailer_dep.rb.tt"))
      expect(content).to include("deliver_later")
    end

    it "mailer dep template has no bare Rage. references" do
      content = File.read(File.join(templates_path, "mailer", "mailer_dep.rb.tt"))
      content.lines.each do |line|
        next if line.include?("RageArch")
        expect(line).not_to match(/\bRage\./),
          "mailer_dep.rb.tt has bare Rage.: #{line.strip}"
      end
    end
  end
end

RSpec.describe "JobGenerator" do
  let(:source) { File.read(File.join(generators_path, "job_generator.rb")) }

  it "exists" do
    expect(File.exist?(File.join(generators_path, "job_generator.rb"))).to eq(true)
  end

  it "has no bare Rage. references" do
    source.lines.each_with_index do |line, idx|
      next if line.include?("RageArch")
      expect(line).not_to match(/\bRage\./),
        "job_generator.rb:#{idx + 1} has bare Rage.: #{line.strip}"
    end
  end

  describe "templates" do
    it "job template exists" do
      expect(File.exist?(File.join(templates_path, "job", "job.rb.tt"))).to eq(true)
    end

    it "job template uses RageArch::UseCase::Base.build" do
      content = File.read(File.join(templates_path, "job", "job.rb.tt"))
      expect(content).to include("RageArch::UseCase::Base.build")
    end

    it "job template inherits from ApplicationJob" do
      content = File.read(File.join(templates_path, "job", "job.rb.tt"))
      expect(content).to include("ApplicationJob")
    end

    it "job template has no bare Rage. references" do
      content = File.read(File.join(templates_path, "job", "job.rb.tt"))
      content.lines.each do |line|
        next if line.include?("RageArch")
        expect(line).not_to match(/\bRage\./),
          "job.rb.tt has bare Rage.: #{line.strip}"
      end
    end
  end
end
