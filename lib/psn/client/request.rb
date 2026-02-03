# frozen_string_literal: true

require 'net/http'
require 'json'

module PSN
  module Client
    # Handles HTTP requests to the PSN API
    class Request
      BASE_URL = 'https://m.np.playstation.com/api'

      def initialize(access_token)
        @access_token = access_token
      end

      def get(path)
        uri = URI("#{BASE_URL}#{path}")

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{@access_token}"
          http.request(request)
        end

        parse_response(response)
      end

      private

      def parse_response(response)
        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          raise Error, "Request failed: #{response.code} #{response.message} - #{response.body}"
        end
      end
    end
  end
end
