# frozen_string_literal: true

require_relative 'pagination'
require_relative 'request'

module PSN
  module Client
    # Handles user and account lookups: search, profiles and played games
    class Users
      include Pagination

      # Paths and quirks below were verified against the live API on 2026-11-22.
      # Player search is the PlayStation App's persisted GraphQL "context" search. The
      # older REST /search/v1/universalSearch POST is blocked at Sony's edge (Akamai
      # 403 HTML, verified 2026-11-22). The query needs the app's client-name header
      # and a displayTitleLocale variable. It returns the first page of results only.
      SEARCH_OPERATION = 'metGetContextSearchResults'
      SEARCH_HASH = 'ac5fb2b82c4d086ca0d272fba34418ab327a7762dd2cd620e63f175bbc5aff10'
      SEARCH_CONTEXT = 'MobileUniversalSearchSocial'
      SEARCH_LOCALE = 'en-US'
      SEARCH_HEADERS = { 'apollographql-client-name' => 'PlayStationApp-Android' }.freeze
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
        variables = { 'searchTerm' => term, 'searchContext' => SEARCH_CONTEXT, 'displayTitleLocale' => SEARCH_LOCALE }
        @request.graphql(SEARCH_OPERATION, variables, SEARCH_HASH, headers: SEARCH_HEADERS)
      end

      # Exact lookup via the profile, which carries the numeric account ID. Search is
      # not used: it is fuzzy, and it leaves the authenticated account out of results.
      def account_id(online_id)
        id = profile(online_id: online_id)&.dig('accountId').to_s
        raise Error, "no PSN account found for #{online_id.inspect}" if id.empty?

        id
      end

      def profile(online_id:)
        unless online_id.is_a?(String) && ONLINE_ID_PATTERN.match?(online_id)
          raise ArgumentError, "invalid PSN online ID: #{online_id.inspect}"
        end

        response = @request.get(format(PROFILE2_PATH, online_id), host: :community,
                                                                  params: { 'fields' => PROFILE2_FIELDS })
        response&.dig('profile')
      end

      def profile_by_account_id(account_id:)
        raise ArgumentError, "invalid PSN account ID: #{account_id.inspect}" unless account_id.to_s.match?(/\A\d+\z/)

        @request.get(format(PROFILE_BY_ACCOUNT_PATH, account_id))
      end

      def played_games(user_id: 'me', limit: PLAYED_GAMES_MAX_LIMIT, offset: 0)
        raise ArgumentError, "invalid PSN user ID: #{user_id.inspect}" unless user_id.to_s.match?(USER_ID_PATTERN)

        validate_page_param!('limit', limit, min: 1, max: PLAYED_GAMES_MAX_LIMIT)
        validate_page_param!('offset', offset, min: 0)

        @request.get(format(PLAYED_GAMES_PATH, user_id), params: { 'limit' => limit, 'offset' => offset })
      end
    end
  end
end
