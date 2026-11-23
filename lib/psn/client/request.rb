# frozen_string_literal: true

require 'net/http'
require 'json'
require_relative 'errors'
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

        perform(uri, authorize(Net::HTTP::Get.new(uri), headers)).first
      end

      def post(path, body, host: :mobile, headers: {})
        uri = build_uri(host, path, {})
        request = authorize(Net::HTTP::Post.new(uri), headers)
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)

        perform(uri, request).first
      end

      def graphql(operation_name, variables, sha256_hash, host: :mobile, headers: {})
        params = {
          'operationName' => operation_name,
          'variables' => JSON.generate(variables),
          'extensions' => JSON.generate('persistedQuery' => { 'version' => 1, 'sha256Hash' => sha256_hash })
        }
        uri = build_uri(host, GRAPHQL_PATH, params)
        request = authorize(Net::HTTP::Get.new(uri), { 'Apollo-Require-Preflight' => 'true' }.merge(headers))
        result, response = perform(uri, request)
        raise_graphql_errors(result, response)
        result
      end

      private

      def authorize(request, headers)
        request['Authorization'] = "Bearer #{@access_token}"
        request['User-Agent'] = USER_AGENT
        headers.each { |name, value| request[name] = value }
        request
      end

      def raise_graphql_errors(result, response)
        errors = result['errors'] if result.is_a?(Hash)
        return unless errors.is_a?(Array) && !errors.empty?

        messages = errors.filter_map { |error| error.is_a?(Hash) ? error['message'] : error.to_s }
        raise GraphQLError.new("PSN GraphQL error: #{messages.join('; ')}",
                               errors: errors, data: result['data'], **Error.details_from(response))
      end

      def build_uri(host, path, params)
        url = "#{HOSTS.fetch(host)}#{path}"
        unless params.empty?
          separator = url.include?('?') ? '&' : '?'
          url = "#{url}#{separator}#{URI.encode_www_form(params)}"
        end
        URI(url)
      end

      # Returns the parsed body and the raw response.
      def perform(uri, http_request)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(http_request)
        end

        [parse_response(response), response]
      rescue *TransportError::NETWORK_ERRORS => e
        raise TransportError, "Request to #{uri.hostname} failed: #{e.class}: #{e.message}"
      end

      def parse_response(response)
        raise error_class_for(response).new(failure_message(response), **Error.details_from(response)) \
          unless response.is_a?(Net::HTTPSuccess)

        return if response.body.nil? || response.body.empty?

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise ParseError.new("Invalid JSON in response: #{e.message}", **Error.details_from(response))
        end
      end

      def error_class_for(response)
        case response.code
        when '401' then AuthenticationError
        when '429' then RateLimitError
        when '403' then privacy_error?(response) ? PrivacyError : Error
        else Error
        end
      end

      def failure_message(response)
        "Request failed: #{response.code} #{response.message} - #{response.body}"
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
