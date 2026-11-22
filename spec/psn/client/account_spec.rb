# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Account do
  subject(:account) { described_class.new(access_token) }

  let(:access_token) { 'access_token' }
  let(:request) { instance_double(PSN::Client::Request) }
  let(:body) { { 'data' => {} } }

  before do
    allow(PSN::Client::Request).to receive(:new).with(access_token).and_return(request)
  end

  describe '#devices' do
    before do
      allow(request).to receive(:get).with('/api/v1/devices/accounts/me', host: :dms,
                                                                          params: described_class::DEVICES_PARAMS)
                                     .and_return(body)
    end

    it 'fetches devices from the DMS host' do
      expect(account.devices).to eq(body)
    end
  end

  describe '#library' do
    before do
      allow(request).to receive(:graphql)
        .with('getUserGameList', { 'categories' => 'ps4_game,ps5_native_game', 'limit' => 100 },
              described_class::LIBRARY_HASH).and_return(body)
    end

    it 'fetches the library' do
      expect(account.library).to eq(body)
    end

    it 'rejects a library limit over 100' do
      expect { account.library(limit: 101) }.to raise_error(ArgumentError)
    end
  end

  describe '#purchased_games' do
    before do
      allow(request).to receive(:graphql)
        .with('getPurchasedGameList', described_class::PURCHASED_VARIABLES.merge('size' => 50, 'start' => 10),
              described_class::PURCHASED_HASH).and_return(body)
    end

    it 'fetches purchased games' do
      expect(account.purchased_games(size: 50, start: 10)).to eq(body)
    end
  end

  describe '#summary' do
    before do
      allow(request).to receive(:graphql)
        .with('getProfileOracle', {}, described_class::SUMMARY_HASH,
              host: :web, headers: { 'apollographql-client-name' => 'oracle' }).and_return(body)
    end

    it 'fetches the summary from the web host with the oracle header' do
      expect(account.summary).to eq(body)
    end
  end
end
