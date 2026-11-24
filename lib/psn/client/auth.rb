# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'oauth2'
require 'json'
require_relative 'errors'
require_relative 'tokens'

module PSN
  module Client
    # Acquires PSN tokens, either by exchanging an NPSSO cookie for an authorization code
    # and that code for tokens, or by trading a saved refresh token for new ones.
    class Auth
      AUTH_URL = 'https://ca.account.sony.com/api/authz/v3/'
      # The PlayStation Android app's public OAuth client, the same for every user (see
      # docs/andshrew/APIv2.md). PSN_CLIENT_ID and PSN_BASIC_TOKEN override them.
      DEFAULT_CLIENT_ID = '09515159-7237-4370-9b40-3806e67c0891'
      # Base64 of "<DEFAULT_CLIENT_ID>:<client secret>".
      DEFAULT_BASIC_TOKEN = 'MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A='

      REDIRECT_URI = 'com.scee.psxandroid.scecompcall://redirect'
      SCOPE = 'psn:mobile.v2.core psn:clientapp'
      TIMEOUT_OPTIONS = %i[open_timeout read_timeout write_timeout].freeze

      def self.authenticate(**options)
        new(**options).authenticate
      end

      def self.tokens(**options)
        new(**options).tokens
      end

      def self.refresh(refresh_token, **options)
        new(**options).refresh(refresh_token)
      end

      # Each credential falls back to its environment variable (PSN_NPSSO, PSN_CLIENT_ID,
      # PSN_BASIC_TOKEN), read when it is used, and then to the default. Only #tokens and
      # #authenticate use the NPSSO. Timeouts are in seconds and apply to the authorisation
      # request and to every token request; nil keeps the HTTP library's default.
      def initialize(npsso: nil, client_id: nil, basic_token: nil, **timeouts)
        unknown = timeouts.keys - TIMEOUT_OPTIONS
        raise ArgumentError, "unknown keyword: #{unknown.map(&:inspect).join(', ')}" unless unknown.empty?

        @npsso = npsso
        @client_id = client_id
        @basic_token = basic_token
        @timeouts = timeouts.compact
      end

      # The access token alone; #tokens also returns the refresh token and both expiry times.
      def authenticate
        tokens.access_token
      end

      # Exchanges the NPSSO for a new access token and refresh token.
      def tokens
        PSN.logger.info('Getting new PSN access token')

        code = fetch_auth_code
        PSN.logger.debug { "Fetched authorisation code: #{code}" }

        access_token = fetch_token(code)
        minutes = access_token.expires_in&.div(60) || 'unknown'
        PSN.logger.debug { "Fetched access token which expires in: #{minutes} minutes" }
        PSN.logger.info('Acquired new PSN access token')

        Tokens.from_oauth2(access_token)
      end

      # Trades a refresh token from an earlier #tokens or #refresh for new tokens, without the
      # NPSSO. A refresh token Sony no longer accepts raises AuthenticationError with the
      # error_code "invalid_grant".
      def refresh(refresh_token)
        blank = !refresh_token.is_a?(String) || refresh_token.strip.empty?
        raise ArgumentError, 'a refresh token is required' if blank

        PSN.logger.info('Refreshing PSN access token')
        access_token = fetch_refreshed_token(refresh_token)
        PSN.logger.info('Refreshed PSN access token')

        Tokens.from_oauth2(access_token, fallback_refresh_token: refresh_token)
      end

      private

      def fetch_auth_code
        uri = URI(auth_url)

        response = request_auth_code(uri)
        if response['location'].nil?
          body = parse_json(response.body)
          fail_with(body['error_description'] || 'Failed to fetch PSN auth code, location header missing', response,
                    error_code: body['error'])
        end

        parse_code(response)
      end

      def request_auth_code(uri)
        http_for(uri).request(request_for(uri))
      rescue *TransportError::NETWORK_ERRORS => e
        log_and_raise TransportError.new("PSN authorisation request failed: #{e.class}: #{e.message}")
      end

      def http_for(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        @timeouts.each { |name, seconds| http.public_send("#{name}=", seconds) }
        http
      end

      def request_for(uri)
        request = Net::HTTP::Get.new(uri)
        request['Cookie'] = npsso_cookie
        request
      end

      def fetch_token(code)
        request_token('exchange') do
          client.auth_code.get_token(code, redirect_uri: REDIRECT_URI, token_format: 'jwt',
                                           headers: { Authorization: "Basic #{basic_token}" })
        end
      end

      def fetch_refreshed_token(refresh_token)
        request_token('refresh') do
          client.get_token({ grant_type: 'refresh_token', refresh_token: refresh_token, scope: SCOPE,
                             token_format: 'jwt', headers: { Authorization: "Basic #{basic_token}" } })
        end
      end

      # Runs a token request, turning its failures into this gem's errors. +action+ names the
      # request in the error message.
      def request_token(action)
        yield
      rescue OAuth2::Error, JSON::ParserError, Faraday::Error => e
        log_and_raise token_error(e, action)
      end

      def token_error(error, action)
        case error
        when OAuth2::Error
          response_error("PSN token #{action} failed: #{error.description || error.message}",
                         error.response, error_code: error.code)
        # oauth2 parses the token body before returning the response, so none is available to attach.
        # The JSON error can quote that body, tokens included, so it is left to +cause+.
        when JSON::ParserError then ParseError.new('PSN token response was not valid JSON')
        else TransportError.new("PSN token request failed: #{error.class}: #{error.message}")
        end
      end

      def parse_code(response)
        params = URI.decode_www_form(URI(response['location']).query.to_s).to_h
        return params['code'] if params['code']

        fail_with(get_error_message(params['error'], params['error_description']), response,
                  error_code: params['error'])
      rescue URI::InvalidURIError, ArgumentError => e
        fail_with("PSN authorisation redirect was malformed: #{e.message}", response, error_code: nil)
      end

      def fail_with(message, response, error_code:)
        log_and_raise response_error(message, response, error_code: error_code)
      end

      # A rate limit or a Sony outage says nothing about the credentials, so only the
      # remaining statuses are reported as AuthenticationError.
      def response_error(message, response, error_code:)
        details = Error.details_from(response)
        case details[:status]
        when 429 then RateLimitError.new(message, **details)
        when 500.. then Error.new(message, **details)
        else AuthenticationError.new(message, error_code: error_code, **details)
        end
      end

      def log_and_raise(error)
        PSN.logger.error(error.message)
        raise error
      end

      def parse_json(body)
        parsed = JSON.parse(body.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def get_error_message(error, error_description = nil)
        return error_description if error_description

        if error == 'login_required'
          'PSN authorisation failed, NPSSO code has expired'
        else
          "Unhandled PSN auth error (#{error})"
        end
      end

      def client
        @client ||= OAuth2::Client.new(client_id, '', site: AUTH_URL, connection_opts: { request: @timeouts })
      end

      def auth_url
        client.auth_code.authorize_url(access_type: 'offline', redirect_uri: REDIRECT_URI, scope: SCOPE)
      end

      def npsso_cookie
        "npsso=#{@npsso || ENV.fetch('PSN_NPSSO', nil)}"
      end

      def client_id
        @client_id || ENV.fetch('PSN_CLIENT_ID', DEFAULT_CLIENT_ID)
      end

      def basic_token
        @basic_token || ENV.fetch('PSN_BASIC_TOKEN', DEFAULT_BASIC_TOKEN)
      end
    end
  end
end
