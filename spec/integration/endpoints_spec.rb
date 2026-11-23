# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Calling endpoints over HTTP', :integration do
  let(:session) { PSN::Client::Session.new('access-token') }
  let(:mobile) { HTTPIntegration::MOBILE }

  describe 'a REST endpoint wrapper' do
    let(:url) { "#{mobile}/trophy/v1/users/me/trophyTitles" }

    before { stub_request(:get, url).with(query: hash_including({})).to_return(json_fixture('trophy_titles')) }

    it 'requests the path with its query parameters' do
      session.trophies.trophy_titles(limit: 1, offset: 0)

      expect(a_request(:get, url).with(query: { 'limit' => '1', 'offset' => '0' })).to have_been_made.once
    end

    it 'identifies itself and sends the Bearer token' do
      session.trophies.trophy_titles(limit: 1)

      expect(a_request(:get, url).with(
               query: hash_including({}),
               headers: { 'Authorization' => 'Bearer access-token',
                          'User-Agent' => "psn-client/#{PSN::Client::VERSION}" }
             )).to have_been_made
    end

    it 'returns the parsed response body untouched' do
      expect(session.trophies.trophy_titles(limit: 1)).to eq(JSON.parse(fixture('trophy_titles')))
    end
  end

  describe 'a title-scoped trophy call' do
    let(:url) do
      "#{mobile}/trophy/v1/users/1234567890123456789/npCommunicationIds/NPWR12345_00/trophyGroups/001/trophies"
    end

    before { stub_request(:get, url).with(query: hash_including({})).to_return(body: '{"trophies":[]}') }

    it 'derives the service name from the platform and adds paging' do
      session.trophies.earned_trophies(np_communication_id: 'NPWR12345_00', user_id: '1234567890123456789',
                                       trophy_group_id: '001', platform: 'PS5', limit: 10, offset: 20)

      expect(a_request(:get, url).with(query: { 'npServiceName' => 'trophy2', 'limit' => '10', 'offset' => '20' }))
        .to have_been_made.once
    end
  end

  describe 'a call to another host' do
    let(:url) { 'https://dms.api.playstation.com/api/v1/devices/accounts/me' }

    before { stub_request(:get, url).with(query: hash_including({})).to_return(json_fixture('devices')) }

    it 'requests the DMS host with its fixed parameters' do
      expect(session.account.devices).to include('accountDevices' => [include('deviceType' => 'PS5')])
      expect(a_request(:get, url).with(
               query: { 'includeFields' => 'device,systemData', 'platform' => 'PS5,PS4,PS3,PSVita' }
             )).to have_been_made.once
    end
  end

  describe 'a GraphQL endpoint wrapper' do
    let(:url) { "#{mobile}/graphql/v1/op" }
    let(:query) do
      { 'operationName' => 'getUserGameList',
        'variables' => '{"categories":"ps4_game,ps5_native_game","limit":1}',
        'extensions' => %({"persistedQuery":{"version":1,"sha256Hash":"#{PSN::Client::Account::LIBRARY_HASH}"}}) }
    end

    before { stub_request(:get, url).with(query: hash_including({})).to_return(json_fixture('library')) }

    it 'sends a persisted-query GET with the Apollo preflight header' do
      session.account.library(limit: 1)

      expect(a_request(:get, url).with(query: query, headers: { 'Apollo-Require-Preflight' => 'true' }))
        .to have_been_made.once
    end

    it 'returns the whole GraphQL body, results under "data"' do
      games = session.account.library(limit: 1).dig('data', 'gameLibraryTitlesRetrieve', 'games')

      expect(games).to contain_exactly(include('name' => 'Example Game', 'titleId' => 'CUSA00001_00'))
    end
  end

  describe 'the convenience methods' do
    let(:url) { 'https://us-prof.np.community.playstation.net/userProfile/v1/users/example_user/profile2' }
    let(:response) { json_fixture('profile') }

    before { stub_request(:get, url).with(query: hash_including({})).to_return(response) }

    it 'requests the profile fields from the community host' do
      session.users.profile(online_id: 'example_user')

      expect(a_request(:get, url).with(query: { 'fields' => PSN::Client::Users::PROFILE2_FIELDS }))
        .to have_been_made.once
    end

    it 'returns the hash under "profile" from #profile' do
      expect(session.users.profile(online_id: 'example_user'))
        .to include('onlineId' => 'example_user', 'trophySummary' => include('level' => 300))
    end

    it 'returns the account ID String from #account_id' do
      expect(session.users.account_id('example_user')).to eq('1234567890123456789')
    end

    context 'when the response body is empty' do
      let(:response) { { status: 204 } }

      it 'returns nil from #profile' do
        expect(session.users.profile(online_id: 'example_user')).to be_nil
      end

      it 'raises Error from #account_id' do
        expect { session.users.account_id('example_user') }
          .to raise_error(PSN::Client::Error, /no PSN account found/)
      end
    end
  end
end
