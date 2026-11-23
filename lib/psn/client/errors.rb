# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'time'

module PSN
  module Client
    # Base class for every error the gem raises. When the failure came from an HTTP
    # response, +status+, +headers+ and +body+ hold its details; otherwise they are
    # nil/empty. The underlying exception, if any, is available through +cause+.
    class Error < StandardError
      attr_reader :status, :headers, :body

      # Keyword arguments for +new+ taken from a Net::HTTPResponse or an OAuth2::Response;
      # header names are lowercased. Anything else yields no details.
      def self.details_from(response)
        if response.respond_to?(:each_header)
          { status: Integer(response.code, 10), headers: response.each_header.to_h, body: response.body }
        elsif response.respond_to?(:status)
          { status: response.status, headers: response.headers.to_h.transform_keys(&:downcase), body: response.body }
        else
          {}
        end
      end

      def initialize(message = nil, status: nil, headers: {}, body: nil)
        super(message)
        @status = status
        @headers = headers
        @body = body
      end
    end

    # Authentication failed: an expired or invalid NPSSO, a rejected token exchange,
    # or an API response of HTTP 401. +error_code+ is Sony's OAuth error code
    # (for example "login_required"), when one was given.
    class AuthenticationError < Error
      attr_reader :error_code

      def initialize(message = nil, error_code: nil, **details)
        super(message, **details)
        @error_code = error_code
      end
    end

    # HTTP 403 caused by the target user's privacy settings.
    class PrivacyError < Error; end

    # HTTP 429. +retry_at+ is when Sony says requests will be accepted again, taken
    # from X-RateLimit-Next-Available or Retry-After, or nil when neither is usable.
    # A relative Retry-After is resolved against the time the error was created.
    class RateLimitError < Error
      attr_reader :retry_at

      def initialize(message = nil, **details)
        super
        @retry_at = parse_retry_at(Time.now)
      end

      private

      def parse_retry_at(now)
        next_available = headers['x-ratelimit-next-available']
        return Time.at(Integer(next_available, 10)) if next_available

        retry_after = headers['retry-after']
        return unless retry_after

        retry_after.match?(/\A\d+\z/) ? now + Integer(retry_after, 10) : Time.httpdate(retry_after)
      rescue ArgumentError
        nil
      end
    end

    # A GraphQL response carried +errors+ (raised even on HTTP 200). +data+ holds any
    # partial result Sony returned alongside them.
    class GraphQLError < Error
      attr_reader :errors, :data

      def initialize(message = nil, errors: [], data: nil, **details)
        super(message, **details)
        @errors = errors
        @data = data
      end
    end

    # The request never produced a response: DNS, connection, TLS or timeout failure.
    class TransportError < Error
      NETWORK_ERRORS = [IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
                        Net::ProtocolError, Net::HTTPBadResponse].freeze
    end

    # A successful response (or token exchange) whose body was not valid JSON.
    class ParseError < Error; end
  end
end
