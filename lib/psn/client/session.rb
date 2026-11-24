# frozen_string_literal: true

require_relative 'account'
require_relative 'auth'
require_relative 'request'
require_relative 'tokens'
require_relative 'trophies'
require_relative 'users'

module PSN
  module Client
    # Shares one Request, and so one access token and transport configuration,
    # across the API classes. A session keeps the access token it was built with: once
    # that expires, build another with Session.from_refresh_token.
    class Session
      # +tokens+ is the Tokens the session was built from, or nil when it was built from
      # an access token string or an injected request.
      attr_reader :request, :tokens

      # Authenticates with the NPSSO and returns a session for the new tokens. Timeouts (in
      # seconds) apply to authentication and to the session's requests; other options are
      # passed to Auth.new.
      def self.authenticate(open_timeout: nil, read_timeout: nil, write_timeout: nil, **auth_options)
        timeouts = { open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: write_timeout }.compact
        new(Auth.tokens(**auth_options, **timeouts), **timeouts)
      end

      # Trades a saved refresh token for new tokens, without the NPSSO, and returns a session
      # for them. Takes the same options as Session.authenticate.
      def self.from_refresh_token(refresh_token, open_timeout: nil, read_timeout: nil, write_timeout: nil,
                                  **auth_options)
        timeouts = { open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: write_timeout }.compact
        new(Auth.refresh(refresh_token, **auth_options, **timeouts), **timeouts)
      end

      # Pass an access token string or a Tokens, optionally with timeouts for the Request
      # built from it, or `request:` to inject a Request (or any object responding to the
      # same methods) instead of building one.
      def initialize(access_token = nil, request: nil, **timeouts)
        @tokens = access_token if access_token.is_a?(Tokens)
        @request = Request.for(@tokens ? @tokens.access_token : access_token, request, **timeouts)
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
