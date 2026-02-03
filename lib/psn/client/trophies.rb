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
    end
  end
end
