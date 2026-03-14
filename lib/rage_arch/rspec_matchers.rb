# frozen_string_literal: true

module RageArch
  # RSpec matchers and helpers for testing RageArch use cases and results.
  # In spec_helper.rb or rails_helper.rb add:
  #   require "rage_arch/rspec_matchers"
  # Then use: expect(result).to succeed_with(post: post) or expect(result).to fail_with_errors(["error"])
  module RSpecMatchers
    # Matcher: expect(result).to succeed_with(key: value, ...)
    # Asserts result.success? and that result.value (when a Hash) includes the given key/value pairs.
    # When result.value is not a Hash, pass a single expected value: expect(result).to succeed_with(42)
    def succeed_with(*expected_list, **expected_hash)
      SucceedWithMatcher.new(expected_list, expected_hash)
    end

    # Matcher: expect(result).to fail_with_errors(errors)
    # Asserts result.failure? and that result.errors matches the given errors (array or RSpec matcher).
    def fail_with_errors(errors)
      FailWithErrorsMatcher.new(errors)
    end

    class SucceedWithMatcher
      include RSpec::Matchers::Composable

      def initialize(expected_list, expected_hash)
        @expected_list = expected_list
        @expected_hash = expected_hash
      end

      def matches?(result)
        @result = result
        return false unless result.respond_to?(:success?) && result.success?

        if @expected_hash.any?
          return false unless result.value.is_a?(Hash)
          value = result.value
          @expected_hash.all? do |k, v|
            val = value.key?(k) ? value[k] : value[k.to_s]
            values_match?(v, val)
          end
        elsif @expected_list.one?
          values_match?(@expected_list.first, result.value)
        else
          @expected_list.empty? ? true : values_match?(@expected_list, result.value)
        end
      end

      def failure_message
        return "expected success but got failure (errors: #{@result.errors.inspect})" if @result.respond_to?(:failure?) && @result.failure?
        return "expected result.value to match" unless @result.respond_to?(:value)
        "expected result.value #{@result.value.inspect} to match #{description}"
      end

      def description
        if @expected_hash.any?
          "succeed with #{@expected_hash.inspect}"
        else
          "succeed with #{@expected_list.inspect}"
        end
      end
    end

    class FailWithErrorsMatcher
      include RSpec::Matchers::Composable

      def initialize(errors)
        @expected_errors = errors
      end

      def matches?(result)
        @result = result
        return false unless result.respond_to?(:failure?) && result.failure?
        return false unless result.respond_to?(:errors)
        values_match?(@expected_errors, @result.errors)
      end

      def failure_message
        if @result.respond_to?(:success?) && @result.success?
          "expected failure but got success (value: #{@result.value.inspect})"
        else
          "expected result.errors #{@result.errors.inspect} to match #{@expected_errors.inspect}"
        end
      end

      def description
        "fail with errors #{@expected_errors.inspect}"
      end
    end
  end
end

RSpec.configure do |config|
  config.include RageArch::RSpecMatchers
end
