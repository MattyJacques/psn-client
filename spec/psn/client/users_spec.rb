# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Users do
  subject(:users) { described_class.new(access_token) }

  let(:access_token) { 'access_token' }
  let(:request) { instance_double(PSN::Client::Request) }

  before do
    allow(PSN::Client::Request).to receive(:new).with(access_token).and_return(request)
  end

  describe '#search' do
    let(:variables) do
      { 'searchTerm' => 'Foo', 'searchContext' => 'MobileUniversalSearchSocial', 'displayTitleLocale' => 'en-US' }
    end
    let(:headers) { { 'apollographql-client-name' => 'PlayStationApp-Android' } }

    it 'returns the raw GraphQL search response' do
      allow(request).to receive(:graphql).with('metGetContextSearchResults', variables,
                                               described_class::SEARCH_HASH, headers: headers)
                                         .and_return('data' => {})
      expect(users.search('Foo')).to eq('data' => {})
    end
  end

  describe '#account_id' do
    let(:profile_params) { { host: :community, params: { 'fields' => described_class::PROFILE2_FIELDS } } }

    it 'returns the account ID from the profile' do
      allow(request).to receive(:get).with('/userProfile/v1/users/Foo/profile2', **profile_params)
                                     .and_return('profile' => { 'accountId' => '2' })
      expect(users.account_id('Foo')).to eq('2')
    end

    it 'raises Error when the profile has no accountId' do
      allow(request).to receive(:get).and_return('profile' => {})
      expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
    end

    it 'raises Error when the response has no profile' do
      allow(request).to receive(:get).and_return({})
      expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
    end

    it 'rejects an invalid online ID' do
      expect { users.account_id('me') }.to raise_error(ArgumentError)
    end
  end

  describe '#profile' do
    it 'returns the profile hash' do
      params = { 'fields' => described_class::PROFILE2_FIELDS }
      allow(request).to receive(:get).with('/userProfile/v1/users/Foo/profile2', host: :community, params: params)
                                     .and_return('profile' => { 'onlineId' => 'Foo' })
      expect(users.profile(online_id: 'Foo')).to eq('onlineId' => 'Foo')
    end

    it 'rejects me' do
      expect { users.profile(online_id: 'me') }.to raise_error(ArgumentError)
    end

    it 'rejects nil' do
      expect { users.profile(online_id: nil) }.to raise_error(ArgumentError)
    end
  end

  describe '#profile_by_account_id' do
    it 'returns the body' do
      allow(request).to receive(:get).with('/userProfile/v1/internal/users/123/profiles').and_return('a' => 1)
      expect(users.profile_by_account_id(account_id: '123')).to eq('a' => 1)
    end

    it 'rejects me' do
      expect { users.profile_by_account_id(account_id: 'me') }.to raise_error(ArgumentError)
    end
  end

  describe '#played_games' do
    it 'requests the defaults' do
      allow(request).to receive(:get).with('/gamelist/v2/users/me/titles', params: { 'limit' => 200, 'offset' => 0 })
                                     .and_return('titles' => [])
      expect(users.played_games).to eq('titles' => [])
    end

    it 'passes user_id, limit and offset through' do
      allow(request).to receive(:get).with('/gamelist/v2/users/9/titles', params: { 'limit' => 5, 'offset' => 10 })
                                     .and_return('titles' => [1])
      expect(users.played_games(user_id: '9', limit: 5, offset: 10)).to eq('titles' => [1])
    end

    it 'accepts me and numeric user IDs' do
      allow(request).to receive(:get).and_return({})
      expect { users.played_games(user_id: 'me') && users.played_games(user_id: '123') }.not_to raise_error
    end

    it 'rejects user IDs that could alter the path' do
      ['1/../x', '1?limit=999'].each do |bad|
        expect { users.played_games(user_id: bad) }.to raise_error(ArgumentError, /invalid PSN user ID/)
      end
    end

    it 'rejects a limit above the maximum' do
      expect { users.played_games(limit: 201) }.to raise_error(ArgumentError)
    end
  end
end
