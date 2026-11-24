# frozen_string_literal: true

module PSN
  module Client
    # The access token and refresh token from one PSN token response, with the time each
    # expires (nil when the response did not say). The token values are secrets, so
    # #inspect and #to_s leave them out.
    class Tokens
      attr_reader :access_token, :expires_at, :refresh_token, :refresh_token_expires_at

      # Builds Tokens from the oauth2 gem's token. The refresh token's lifetime is counted
      # from +now+, and +fallback_refresh_token+ is kept when the response carries none.
      def self.from_oauth2(oauth_token, fallback_refresh_token: nil, now: Time.now)
        lifetime = Integer(oauth_token.params['refresh_token_expires_in'], exception: false)

        new(access_token: oauth_token.token,
            expires_at: oauth_token.expires_at && Time.at(oauth_token.expires_at),
            refresh_token: [oauth_token.refresh_token, fallback_refresh_token].find { |token| !token.to_s.empty? },
            refresh_token_expires_at: lifetime && (now + lifetime))
      end

      def initialize(access_token:, expires_at: nil, refresh_token: nil, refresh_token_expires_at: nil)
        @access_token = access_token
        @expires_at = expires_at
        @refresh_token = refresh_token
        @refresh_token_expires_at = refresh_token_expires_at
        freeze
      end

      # False when the expiry time is unknown.
      def expired?(now = Time.now)
        past?(expires_at, now)
      end

      # False when the expiry time is unknown.
      def refresh_token_expired?(now = Time.now)
        past?(refresh_token_expires_at, now)
      end

      def inspect
        "#<#{self.class.name} expires_at=#{expires_at.inspect} " \
          "refresh_token_expires_at=#{refresh_token_expires_at.inspect}>"
      end
      alias to_s inspect

      private

      def past?(time, now)
        !time.nil? && now >= time
      end
    end
  end
end
