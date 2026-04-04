# frozen_string_literal: true

require "rails/generators/base"

module RageArch
  module Generators
    class JobGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :use_case_symbol, type: :string, required: false, default: nil, banner: "use_case_symbol"

      desc "Generate an ActiveJob that runs a RageArch use case by symbol."
      def create_job
        template "job/job.rb.tt", File.join("app/jobs", "#{file_name}_job.rb")
      end

      private

      def job_class_name
        file_name.camelize
      end

      def inferred_symbol
        use_case_symbol || file_name
      end
    end
  end
end
