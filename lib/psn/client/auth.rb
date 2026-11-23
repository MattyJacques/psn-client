# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'oauth2'
require 'json'
require_relative 'errors'

module PSN
  module Client
    # Handles acquiring PSN access tokens by exchanging an NPSSO cookie
    # for an authorization code and then exchanging that code for a token.
    class Auth
      AUTH_URL = 'https://ca.account.sony.com/api/authz/v3/'
      # The PlayStation Android app's public OAuth client, the same for every user (see
      # docs/andshrew/APIv2.md). PSN_CLIENT_ID and PSN_BASIC_TOKEN override them.
      DEFAULT_CLIENT_ID = '09515159-7237-4370-9b40-3806e67c0891'
      # Base64 of "<DEFAULT_CLIENT_ID>:<client secret>".
      DEFAULT_BASIC_TOKEN = 'MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A='
      BASIC_TOKEN = ENV.fetch('PSN_BASIC_TOKEN', DEFAULT_BASIC_TOKEN)

      class << self
        def authenticate
          new.authenticate
        end
      end

      def authenticate
        PSN.logger.info('Getting new PSN access token')

        code = fetch_auth_code
        PSN.logger.debug { "Fetched authorisation code: #{code}" }

        access_token = fetch_token(code)
        PSN.logger.debug { "Fetched access token which expires in: #{access_token.expires_in / 60} minutes" }
        PSN.logger.info('Acquired new PSN access token')

        access_token.token
      end

      private

      def fetch_auth_code
        uri = URI(auth_url)

        response = request_auth_code(uri)
        if response['location'].nil?
          body = parse_json(response.body)
          fail_with(extract_error_message(body), response, error_code: body['error'])
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
        http
      end

      def request_for(uri)
        request = Net::HTTP::Get.new(uri)
        request['Cookie'] = npsso_cookie
        request
      end

      def fetch_token(code)
        client.auth_code.get_token(code,
                                   redirect_uri: 'com.scee.psxandroid.scecompcall://redirect',
                                   token_format: 'jwt',
                                   headers: { Authorization: "Basic #{BASIC_TOKEN}" })
      rescue OAuth2::Error => e
        log_and_raise AuthenticationError.new("PSN token exchange failed: #{e.description || e.message}",
                                              error_code: e.code, **oauth_response_details(e.response))
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
        log_and_raise TransportError.new("PSN token request failed: #{e.class}: #{e.message}")
      end

      def parse_code(response)
        params = URI.decode_www_form(URI(response['location']).query.to_s).to_h
        code = params['code']

        return code if code

        fail_with(get_error_message(params['error'], params['error_description']), response,
                  error_code: params['error'])
      end

      def fail_with(message, response, error_code:)
        log_and_raise AuthenticationError.new(message, error_code: error_code, **Error.details_from(response))
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

      def extract_error_message(body)
        body['error_description'] || 'Failed to fetch PSN auth code, location header missing'
      end

      def oauth_response_details(response)
        return {} unless response.respond_to?(:status)

        { status: response.status, headers: response.headers.to_h.transform_keys(&:downcase), body: response.body }
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
        @client ||= OAuth2::Client.new(ENV.fetch('PSN_CLIENT_ID', DEFAULT_CLIENT_ID), '', site: AUTH_URL)
      end

      def auth_url
        client.auth_code.authorize_url(access_type: 'offline',
                                       redirect_uri: 'com.scee.psxandroid.scecompcall://redirect',
                                       scope: 'psn:mobile.v2.core psn:clientapp')
      end

      def npsso_cookie
        "npsso=#{ENV.fetch('PSN_NPSSO', nil)}"
      end
    end
  end
end
