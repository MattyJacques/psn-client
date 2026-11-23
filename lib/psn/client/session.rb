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

      # Authenticates and returns a session for the new token. Timeouts (in seconds) apply to
      # authentication and to the session's requests; other options are passed to Auth.new.
      def self.authenticate(open_timeout: nil, read_timeout: nil, write_timeout: nil, **auth_options)
        timeouts = { open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: write_timeout }.compact
        new(Auth.authenticate(**auth_options, **timeouts), **timeouts)
      end

      # Pass an access token, optionally with timeouts for the Request built from it, or
      # `request:` to inject a Request (or any object responding to the same methods)
      # instead of building one.
      def initialize(access_token = nil, request: nil, **timeouts)
        @request = Request.for(access_token, request, **timeouts)
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
