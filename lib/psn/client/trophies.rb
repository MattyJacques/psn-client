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

      def title_trophies(np_communication_id:, trophy_group_id: 'all', np_service_name: nil, platform: nil, **options)
        query_params = {
          npServiceName: resolve_service_name(np_service_name, platform),
          limit: options[:limit],
          offset: options[:offset]
        }.compact

        query_string = query_params.map { |k, v| "#{k}=#{v}" }.join('&')

        path = "/trophy/v1/npCommunicationIds/#{np_communication_id}/trophyGroups/#{trophy_group_id}/trophies"
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
    end
  end
end
