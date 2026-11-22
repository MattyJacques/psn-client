# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Users do
  subject(:users) { described_class.new(access_token) }

  let(:access_token) { 'access_token' }
  let(:request) { instance_double(PSN::Client::Request) }
  let(:search_path) { '/search/v1/universalSearch' }
  let(:search_body) { { 'searchTerm' => 'Foo', 'domainRequests' => [{ 'domain' => 'SocialAllAccounts' }] } }

  before do
    allow(PSN::Client::Request).to receive(:new).with(access_token).and_return(request)
  end

  def results(*ids)
    entries = ids.map { |id, acc| { 'socialMetadata' => { 'onlineId' => id, 'accountId' => acc } } }
    { 'domainResponses' => [{ 'results' => entries }] }
  end

  describe '#search' do
    it 'returns the raw search response, near-matches included' do
      allow(request).to receive(:post).with(search_path, search_body).and_return(results(%w[Foo_Bar 1]))
      expect(users.search('Foo')).to eq(results(%w[Foo_Bar 1]))
    end
  end

  describe '#account_id' do
    it 'returns the account ID of the case-insensitive exact match' do
      allow(request).to receive(:post).with(search_path, search_body)
                                      .and_return(results(%w[Foo_Bar 1], %w[foo 2]))
      expect(users.account_id('Foo')).to eq('2')
    end

    it 'raises Error when only a near-match comes back' do
      allow(request).to receive(:post).and_return(results(%w[Foo_Bar 1]))
      expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
    end

    it 'raises Error when domainResponses is missing' do
      allow(request).to receive(:post).and_return({})
      expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
    end
  end

  describe '#account_id without an accountId' do
    it 'raises Error rather than returning an empty string' do
      allow(request).to receive(:post).and_return(results(['Foo', nil]))
      expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
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
