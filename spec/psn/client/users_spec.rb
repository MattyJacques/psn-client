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

    before do
      allow(request).to receive(:graphql).with('metGetContextSearchResults', variables,
                                               described_class::SEARCH_HASH, headers: headers)
                                         .and_return('data' => {})
    end

    it 'returns the raw GraphQL search response' do
      expect(users.search('Foo')).to eq('data' => {})
    end
  end

  describe '#account_id' do
    let(:profile_params) { { host: :community, params: { 'fields' => described_class::PROFILE2_FIELDS } } }
    let(:response) { { 'profile' => { 'accountId' => '2' } } }

    before do
      allow(request).to receive(:get).with('/userProfile/v1/users/Foo/profile2', **profile_params)
                                     .and_return(response)
    end

    it 'returns the account ID from the profile' do
      expect(users.account_id('Foo')).to eq('2')
    end

    it 'rejects an invalid online ID' do
      expect { users.account_id('me') }.to raise_error(ArgumentError)
    end

    context 'when the profile has no accountId' do
      let(:response) { { 'profile' => {} } }

      it 'raises Error' do
        expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
      end
    end

    context 'when the response has no profile' do
      let(:response) { {} }

      it 'raises Error' do
        expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
      end
    end
  end

  describe 'an empty profile response' do
    before do
      allow(request).to receive(:get).and_return(nil)
    end

    it 'returns nil from #profile' do
      expect(users.profile(online_id: 'Foo')).to be_nil
    end

    it 'raises Error from #account_id' do
      expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
    end
  end

  describe '#profile' do
    before do
      allow(request).to receive(:get)
        .with('/userProfile/v1/users/Foo/profile2', host: :community,
                                                    params: { 'fields' => described_class::PROFILE2_FIELDS })
        .and_return('profile' => { 'onlineId' => 'Foo' })
    end

    it 'returns the profile hash' do
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
    before do
      allow(request).to receive(:get).with('/userProfile/v1/internal/users/123/profiles').and_return('a' => 1)
    end

    it 'returns the body' do
      expect(users.profile_by_account_id(account_id: '123')).to eq('a' => 1)
    end

    it 'rejects me' do
      expect { users.profile_by_account_id(account_id: 'me') }.to raise_error(ArgumentError)
    end
  end

  describe '#played_games' do
    before do
      allow(request).to receive(:get).and_return('titles' => [])
    end

    it 'returns the body' do
      expect(users.played_games).to eq('titles' => [])
    end

    it 'requests the defaults' do
      users.played_games
      expect(request).to have_received(:get)
        .with('/gamelist/v2/users/me/titles', params: { 'limit' => 200, 'offset' => 0 })
    end

    it 'passes user_id, limit and offset through' do
      users.played_games(user_id: '9', limit: 5, offset: 10)
      expect(request).to have_received(:get)
        .with('/gamelist/v2/users/9/titles', params: { 'limit' => 5, 'offset' => 10 })
    end

    it 'accepts me' do
      expect { users.played_games(user_id: 'me') }.not_to raise_error
    end

    it 'accepts a numeric user ID' do
      expect { users.played_games(user_id: '123') }.not_to raise_error
    end

    it 'rejects user IDs that could alter the path' do
      ['1/../x', '1?limit=999'].each do |bad|
        expect { users.played_games(user_id: bad) }.to raise_error(ArgumentError, /invalid PSN user ID/)
      end
    end

    it 'rejects a limit above the maximum' do
      expect { users.played_games(limit: 201) }
        .to raise_error(ArgumentError, 'limit must be an Integer between 1 and 200, got 201')
    end

    it 'rejects a limit below 1 or not an Integer' do
      [0, -1, 1.5, '5', nil].each do |bad|
        expect { users.played_games(limit: bad) }.to raise_error(ArgumentError, /limit must be an Integer/)
      end
    end

    it 'rejects a negative or non-Integer offset' do
      [-1, 1.5, '0', nil].each do |bad|
        expect { users.played_games(offset: bad) }.to raise_error(ArgumentError, /offset must be an Integer at least 0/)
      end
    end
  end

  context 'with an injected request' do
    subject(:injected) { described_class.new(request: request) }

    before do
      allow(PSN::Client::Request).to receive(:new)
      allow(request).to receive(:get).and_return('ok')
    end

    it 'uses it without building a Request' do
      expect(injected.profile_by_account_id(account_id: '1')).to eq('ok')
      expect(request).to have_received(:get).with('/userProfile/v1/internal/users/1/profiles')
      expect(PSN::Client::Request).not_to have_received(:new)
    end

    it 'requires an access token or a request' do
      expect { described_class.new }.to raise_error(ArgumentError, /access token or a request/)
    end
  end
end
