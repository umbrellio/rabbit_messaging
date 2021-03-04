# frozen_string_literal: true

require "bundler/setup"
require "simplecov"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config do |c|
  c.report_with_single_file = true
  c.lcov_file_name = "lcov.info"
  c.output_directory = "coverage"
end

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::LcovFormatter,
])

SimpleCov.enable_coverage(:branch)
SimpleCov.enable_coverage(:line)
SimpleCov.add_filter "spec"
SimpleCov.start

require "rabbit_messaging"

require "rspec/its"
require "pry"
require "exception_notification"
require "ipaddr"

require_relative "../environments/development"
require_relative "support/spec_support"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!

  config.default_formatter = "doc" if config.files_to_run.one?
  config.expose_dsl_globally = true
end
