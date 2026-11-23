# frozen_string_literal: true

require_relative 'request'
require_relative 'pagination'

module PSN
  module Client
    # Handles trophy-related API requests
    class Trophies
      include Pagination

      # Sony answers HTTP 400 for a trophy titles limit above 800. The per-title
      # trophy lists accept any limit of at least 1 (probed up to 100,000), so they
      # get no upper bound. Verified against the live API on 2026-11-23.
      TROPHY_TITLES_MAX_LIMIT = 800

      # Pass an access token, or `request:` to inject a Request (or any object
      # responding to the same methods) instead of building one.
      def initialize(access_token = nil, request: nil)
        @request = Request.for(access_token, request)
      end

      def trophy_titles(user_id: 'me', limit: TROPHY_TITLES_MAX_LIMIT, offset: 0)
        validate_page_param!('limit', limit, min: 1, max: TROPHY_TITLES_MAX_LIMIT)
        validate_page_param!('offset', offset, min: 0)

        @request.get("/trophy/v1/users/#{user_id}/trophyTitles", params: { 'limit' => limit, 'offset' => offset })
      end

      def trophy_summary(user_id: 'me')
        path = "/trophy/v1/users/#{user_id}/trophySummary"
        @request.get(path)
      end

      def title_trophy_groups(np_communication_id:, np_service_name: nil, platform: nil)
        path = "/trophy/v1/npCommunicationIds/#{np_communication_id}/trophyGroups"
        @request.get(path, params: title_params(np_service_name, platform))
      end

      def earned_trophy_groups(np_communication_id:, user_id: 'me', np_service_name: nil, platform: nil)
        path = "/trophy/v1/users/#{user_id}/npCommunicationIds/#{np_communication_id}/trophyGroups"
        @request.get(path, params: title_params(np_service_name, platform))
      end

      # `limit:` and `offset:` are optional; without a limit the API returns every trophy.
      def title_trophies(np_communication_id:, trophy_group_id: 'all', np_service_name: nil, platform: nil,
                         limit: nil, offset: nil)
        path = "/trophy/v1/npCommunicationIds/#{np_communication_id}/trophyGroups/#{trophy_group_id}/trophies"
        @request.get(path, params: title_params(np_service_name, platform, limit: limit, offset: offset))
      end

      def earned_trophies(np_communication_id:, user_id: 'me', trophy_group_id: 'all', np_service_name: nil,
                          platform: nil, limit: nil, offset: nil)
        path = "/trophy/v1/users/#{user_id}/npCommunicationIds/#{np_communication_id}" \
               "/trophyGroups/#{trophy_group_id}/trophies"
        @request.get(path, params: title_params(np_service_name, platform, limit: limit, offset: offset))
      end

      private

      # Query parameters for the title-scoped endpoints; anything left nil is omitted.
      def title_params(service_name, platform, limit: nil, offset: nil)
        validate_page_param!('limit', limit, min: 1) unless limit.nil?
        validate_page_param!('offset', offset, min: 0) unless offset.nil?

        service_name = resolve_service_name(service_name, platform)
        { 'npServiceName' => service_name, 'limit' => limit, 'offset' => offset }.compact
      end

      def resolve_service_name(service_name, platform)
        raise ArgumentError, 'Provide either np_service_name or platform, not both' if service_name && platform

        return service_name if service_name

        if %w[PS3 PS4 PSVita].include?(platform)
          'trophy'
        elsif %w[PS5 PC].include?(platform)
          'trophy2'
        end
      end
    end
  end
end
