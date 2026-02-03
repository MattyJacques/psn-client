# frozen_string_literal: true

require_relative 'client/auth'
require_relative 'client/request'
require_relative 'client/trophies'
require_relative 'client/version'
require_relative 'logger'
require 'net/http'

module PSN
  module Client
    class Error < StandardError; end
    # Your code goes here...
  end
end
