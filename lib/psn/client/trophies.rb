# frozen_string_literal: true

require_relative 'request'

module PSN
  module Client
    # Handles trophy-related API requests
    class Trophies
      def initialize(access_token)
        @request = Request.new(access_token)
      end

      def trophy_titles(user_id: 'me', limit: 800, offset: 0)
        path = "/trophy/v1/users/#{user_id}/trophyTitles?limit=#{limit}&offset=#{offset}"
        @request.get(path)
      end

      def trophy_summary(user_id: 'me')
        path = "/trophy/v1/users/#{user_id}/trophySummary"
        @request.get(path)
      end

      def title_trophy_groups(np_communication_id:, np_service_name: nil, platform: nil)
        query_string = build_query_string(npServiceName: resolve_service_name(np_service_name, platform))

        path = "/trophy/v1/npCommunicationIds/#{np_communication_id}/trophyGroups?#{query_string}"
        @request.get(path)
      end

      def earned_trophy_groups(np_communication_id:, user_id: 'me', np_service_name: nil, platform: nil)
        query_string = build_query_string(npServiceName: resolve_service_name(np_service_name, platform))

        path = "/trophy/v1/users/#{user_id}/npCommunicationIds/#{np_communication_id}/trophyGroups?#{query_string}"
        @request.get(path)
      end

      def title_trophies(np_communication_id:, trophy_group_id: 'all', np_service_name: nil, platform: nil, **options)
        query_string = build_query_string(
          npServiceName: resolve_service_name(np_service_name, platform),
          limit: options[:limit],
          offset: options[:offset]
        )

        path = "/trophy/v1/npCommunicationIds/#{np_communication_id}/trophyGroups/#{trophy_group_id}/trophies"
        path += "?#{query_string}"
        @request.get(path)
      end

      def earned_trophies(np_communication_id:, user_id: 'me', trophy_group_id: 'all', np_service_name: nil,
                          platform: nil, **options)
        query_string = build_query_string(
          npServiceName: resolve_service_name(np_service_name, platform),
          limit: options[:limit],
          offset: options[:offset]
        )

        path = "/trophy/v1/users/#{user_id}/npCommunicationIds/#{np_communication_id}" \
               "/trophyGroups/#{trophy_group_id}/trophies"
        path += "?#{query_string}"
        @request.get(path)
      end

      private

      def resolve_service_name(service_name, platform)
        raise ArgumentError, 'Provide either np_service_name or platform, not both' if service_name && platform

        return service_name if service_name

        if %w[PS3 PS4 PSVita].include?(platform)
          'trophy'
        elsif %w[PS5 PC].include?(platform)
          'trophy2'
        end
      end

      def build_query_string(**query_params)
        query_params.compact.map { |key, value| "#{key}=#{value}" }.join('&')
      end
    end
  end
end
