# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'oauth2'

module PSN
  module Client
    # Handles acquiring PSN access tokens by exchanging an NPSSO cookie
    # for an authorization code and then exchanging that code for a token.
    class Auth
      AUTH_URL = 'https://ca.account.sony.com/api/authz/v3/'
      BASIC_TOKEN = ENV.fetch('PSN_BASIC_TOKEN', nil)

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

        response = http_for(uri).request(request_for(uri))

        if response['location'].nil?
          message = 'Failed to fetch PSN auth code, location header missing'
          PSN.logger.error(message)
          raise message
        end

        parse_code(response['location'])
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
      end

      def parse_code(location)
        code = location.match(%r{\?code=([A-Za-z0-9:?_\-./=]+)})

        if code
          code[1]
        else
          error = location.match(%r{&error=([A-Za-z0-9:?_\-./=]+)})

          message = get_error_message(error[1])
          PSN.logger.error(message)
          raise message
        end
      end

      def client
        @client ||= OAuth2::Client.new(ENV.fetch('PSN_CLIENT_ID', nil), '', site: AUTH_URL)
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
