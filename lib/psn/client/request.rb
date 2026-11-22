# frozen_string_literal: true

require 'net/http'
require 'json'

module PSN
  module Client
    # Handles HTTP requests to the PSN API
    class Request
      HOSTS = {
        mobile: 'https://m.np.playstation.com/api',
        community: 'https://us-prof.np.community.playstation.net',
        dms: 'https://dms.api.playstation.com',
        web: 'https://web.np.playstation.com/api'
      }.freeze
      BASE_URL = HOSTS[:mobile]
      PRIVACY_PATTERN = /access control|privacy/i

      def initialize(access_token)
        @access_token = access_token
      end

      def get(path, host: :mobile, params: {}, headers: {})
        uri = build_uri(host, path, params)
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@access_token}"
        headers.each { |name, value| request[name] = value }

        perform(uri, request)
      end

      private

      def build_uri(host, path, params)
        url = "#{HOSTS.fetch(host)}#{path}"
        unless params.empty?
          separator = url.include?('?') ? '&' : '?'
          url = "#{url}#{separator}#{URI.encode_www_form(params)}"
        end
        URI(url)
      end

      def perform(uri, http_request)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(http_request)
        end

        parse_response(response)
      end

      def parse_response(response)
        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          message = "Request failed: #{response.code} #{response.message} - #{response.body}"
          raise PrivacyError, message if privacy_error?(response)

          raise Error, message
        end
      end

      def privacy_error?(response)
        return false unless response.code == '403'

        error = JSON.parse(response.body)['error']
        error = error['message'] if error.is_a?(Hash)
        error.is_a?(String) && error.match?(PRIVACY_PATTERN)
      rescue JSON::ParserError, TypeError
        false
      end
    end
  end
end
