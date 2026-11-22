# frozen_string_literal: true

require_relative 'request'

module PSN
  module Client
    # Handles user and account lookups: search, profiles and played games
    class Users
      # Paths and quirks below were verified live in ai-client, 2026-07.
      SEARCH_PATH = '/search/v1/universalSearch'
      SEARCH_DOMAIN = 'SocialAllAccounts'
      PROFILE2_PATH = '/userProfile/v1/users/%s/profile2'
      PROFILE2_FIELDS = 'npId,onlineId,accountId,avatarUrls,plus,aboutMe,languagesUsed,' \
                        'trophySummary(@default,level,progress,earnedTrophies),' \
                        'isOfficiallyVerified,primaryOnlineStatus,' \
                        'presences(@default,@titleInfo,platform,lastOnlineDate)'
      # The internal profiles endpoint rejects "me" as a path account ID (HTTP 400).
      PROFILE_BY_ACCOUNT_PATH = '/userProfile/v1/internal/users/%s/profiles'
      PLAYED_GAMES_PATH = '/gamelist/v2/users/%s/titles'
      # A limit of 201 returns HTTP 400.
      PLAYED_GAMES_MAX_LIMIT = 200
      USER_ID_PATTERN = /\A(me|\d+)\z/
      ONLINE_ID_PATTERN = /\A[a-zA-Z0-9_-]{3,16}\z/

      def initialize(access_token)
        @request = Request.new(access_token)
      end

      def search(term)
        body = { 'searchTerm' => term, 'domainRequests' => [{ 'domain' => SEARCH_DOMAIN }] }
        @request.post(SEARCH_PATH, body)
      end

      def account_id(online_id)
        id = exact_match(online_id)&.dig('accountId').to_s
        raise Error, "no PSN account found for #{online_id.inspect}" if id.empty?

        id
      end

      def profile(online_id:)
        unless online_id.is_a?(String) && ONLINE_ID_PATTERN.match?(online_id)
          raise ArgumentError, "invalid PSN online ID: #{online_id.inspect}"
        end

        response = @request.get(format(PROFILE2_PATH, online_id), host: :community,
                                                                  params: { 'fields' => PROFILE2_FIELDS })
        response['profile']
      end

      def profile_by_account_id(account_id:)
        raise ArgumentError, "invalid PSN account ID: #{account_id.inspect}" unless account_id.to_s.match?(/\A\d+\z/)

        @request.get(format(PROFILE_BY_ACCOUNT_PATH, account_id))
      end

      def played_games(user_id: 'me', limit: PLAYED_GAMES_MAX_LIMIT, offset: 0)
        raise ArgumentError, "invalid PSN user ID: #{user_id.inspect}" unless user_id.to_s.match?(USER_ID_PATTERN)
        raise ArgumentError, "limit must be at most #{PLAYED_GAMES_MAX_LIMIT}" if limit > PLAYED_GAMES_MAX_LIMIT

        @request.get(format(PLAYED_GAMES_PATH, user_id), params: { 'limit' => limit, 'offset' => offset })
      end

      private

      def exact_match(online_id)
        results = search(online_id).dig('domainResponses', 0, 'results') || []
        results.map { |result| result['socialMetadata'] }
               .find { |meta| meta&.dig('onlineId')&.casecmp?(online_id) }
      end
    end
  end
end
