# frozen_string_literal: true

require 'logger'

# Get/Set logger for the gem
module PSN
  # defaults to Rails.logger if in a Rails environment, otherwise logs to STDOUT
  def self.logger
    @logger ||= defined?(Rails) ? Rails.logger : Logger.new($stdout)
  end

  def self.logger=(logger)
    @logger = logger
  end
end
