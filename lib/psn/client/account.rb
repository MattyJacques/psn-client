# frozen_string_literal: true

require_relative 'request'

module PSN
  module Client
    # Handles requests about the authenticated account: devices, library, purchases and summary
    class Account
      # Served by the DMS host, which has no /api suffix, so the path carries it. Verified live in ai-client, 2026-07.
      DEVICES_PATH = '/api/v1/devices/accounts/me'
      DEVICES_PARAMS = { 'includeFields' => 'device,systemData', 'platform' => 'PS5,PS4,PS3,PSVita' }.freeze
      LIBRARY_OPERATION = 'getUserGameList'
      # Persisted query hash (and categories below) verified live in ai-client, 2026-07.
      LIBRARY_HASH = 'e0136f81d7d1fb6be58238c574e9a46e1c0cc2f7f6977a08a5a46f224523a004'
      LIBRARY_CATEGORIES = 'ps4_game,ps5_native_game'
      # A limit above 100 is rejected by Sony; cap verified live in ai-client, 2026-07.
      LIBRARY_MAX_LIMIT = 100
      PURCHASED_OPERATION = 'getPurchasedGameList'
      PURCHASED_HASH = '827a423f6a8ddca4107ac01395af2ec0eafd8396fc7fa204aaf9b7ed2eefa168'
      # Persisted query and variables verified live in ai-client, 2026-07.
      PURCHASED_VARIABLES = {
        'isActive' => true, 'platform' => %w[ps4 ps5], 'sortBy' => 'ACTIVE_DATE', 'sortDirection' => 'desc'
      }.freeze
      SUMMARY_OPERATION = 'getProfileOracle'
      # Persisted query hash verified live in ai-client, 2026-07.
      SUMMARY_HASH = 'fc0d765f537f3dce3e0d91c71e85daa401042ba43066acde9f8f584faced10df'
      # Without this header the call returns HTTP 400 "Cannot query field" (verified live in ai-client, 2026-07-11).
      SUMMARY_HEADERS = { 'apollographql-client-name' => 'oracle' }.freeze

      def initialize(access_token)
        @request = Request.new(access_token)
      end

      def devices
        @request.get(DEVICES_PATH, host: :dms, params: DEVICES_PARAMS)
      end

      def library(limit: LIBRARY_MAX_LIMIT)
        raise ArgumentError, "limit must be at most #{LIBRARY_MAX_LIMIT}" if limit > LIBRARY_MAX_LIMIT

        @request.graphql(LIBRARY_OPERATION, { 'categories' => LIBRARY_CATEGORIES, 'limit' => limit }, LIBRARY_HASH)
      end

      def purchased_games(size: 200, start: 0)
        variables = PURCHASED_VARIABLES.merge('size' => size, 'start' => start)
        @request.graphql(PURCHASED_OPERATION, variables, PURCHASED_HASH)
      end

      def summary
        @request.graphql(SUMMARY_OPERATION, {}, SUMMARY_HASH, host: :web, headers: SUMMARY_HEADERS)
      end
    end
  end
end
