# frozen_string_literal: true

require 'debug'

# Initialise SimpleCov for code coverage measurement
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_group 'Lib', 'lib'
end

require 'psn/client'
# Blocks real network connections in every spec; spec/integration stubs them per example.
require 'webmock/rspec'
require_relative 'support/http_integration'
require_relative 'support/http_responses'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.include HTTPResponses
  config.include HTTPIntegration, :integration

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
