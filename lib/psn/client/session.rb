# frozen_string_literal: true

require_relative 'account'
require_relative 'auth'
require_relative 'request'
require_relative 'trophies'
require_relative 'users'

module PSN
  module Client
    # Shares one Request, and so one access token and transport configuration,
    # across the API classes.
    class Session
      attr_reader :request

      # Authenticates and returns a session for the new token. Options are passed to Auth.new.
      def self.authenticate(**auth_options)
        new(Auth.authenticate(**auth_options))
      end

      # Pass an access token, or `request:` to inject a Request (or any object
      # responding to the same methods) instead of building one.
      def initialize(access_token = nil, request: nil)
        @request = Request.for(access_token, request)
      end

      def trophies
        @trophies ||= Trophies.new(request: request)
      end

      def users
        @users ||= Users.new(request: request)
      end

      def account
        @account ||= Account.new(request: request)
      end
    end
  end
end
