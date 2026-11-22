# frozen_string_literal: true

require 'net/http'
require 'json'
require_relative 'version'

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
      GRAPHQL_PATH = '/graphql/v1/op'
      PRIVACY_PATTERN = /access control|privacy/i
      # Sony's search backend answers HTTP 200 with "Internal server error" when the
      # User-Agent is Net::HTTP's default "Ruby" (verified live 2026-11-22), so every
      # request identifies the gem instead.
      USER_AGENT = "psn-client/#{VERSION}".freeze

      def initialize(access_token)
        @access_token = access_token
      end

      def get(path, host: :mobile, params: {}, headers: {})
        uri = build_uri(host, path, params)

        perform(uri, authorize(Net::HTTP::Get.new(uri), headers))
      end

      def post(path, body, host: :mobile, headers: {})
        uri = build_uri(host, path, {})
        request = authorize(Net::HTTP::Post.new(uri), headers)
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)

        perform(uri, request)
      end

      def graphql(operation_name, variables, sha256_hash, host: :mobile, headers: {})
        params = {
          'operationName' => operation_name,
          'variables' => JSON.generate(variables),
          'extensions' => JSON.generate('persistedQuery' => { 'version' => 1, 'sha256Hash' => sha256_hash })
        }
        result = get(GRAPHQL_PATH, host: host, params: params,
                                   headers: { 'Apollo-Require-Preflight' => 'true' }.merge(headers))
        raise_graphql_errors(result)
        result
      end

      private

      def authorize(request, headers)
        request['Authorization'] = "Bearer #{@access_token}"
        request['User-Agent'] = USER_AGENT
        headers.each { |name, value| request[name] = value }
        request
      end

      def raise_graphql_errors(result)
        errors = result['errors'] if result.is_a?(Hash)
        return unless errors.is_a?(Array) && !errors.empty?

        messages = errors.filter_map { |error| error.is_a?(Hash) ? error['message'] : error.to_s }
        raise Error, "PSN GraphQL error: #{messages.join('; ')}"
      end

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

        body = JSON.parse(response.body)
        error = body['error'] if body.is_a?(Hash)
        error = error['message'] if error.is_a?(Hash)
        error.is_a?(String) && error.match?(PRIVACY_PATTERN)
      rescue JSON::ParserError, TypeError
        false
      end
    end
  end
end
