# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Trophies do
  subject(:trophies) { described_class.new(access_token) }

  let(:access_token) { 'access_token' }
  let(:request) { instance_double(PSN::Client::Request) }

  describe '#trophy_titles' do
    let(:response) { { 'trophyTitles' => [] } }

    before do
      allow(PSN::Client::Request).to receive(:new).with(access_token).and_return(request)
      allow(request).to receive(:get).with('/trophy/v1/users/me/trophyTitles?limit=800&offset=0').and_return(response)
    end

    it 'delegates to Request' do
      expect(trophies.trophy_titles).to eq(response)
    end

    context 'with parameters' do
      before do
        allow(request).to receive(:get).with('/trophy/v1/users/other/trophyTitles?limit=10&offset=5')
                                       .and_return(response)
      end

      it 'passes parameters correctly' do
        expect(trophies.trophy_titles(user_id: 'other', limit: 10, offset: 5)).to eq(response)
      end
    end
  end

  describe '#title_trophies' do
    let(:response) { { 'trophies' => [] } }
    let(:np_comm_id) { 'NPWR12345_00' }

    before do
      allow(PSN::Client::Request).to receive(:new).with(access_token).and_return(request)
      allow(request).to receive(:get).and_return(response)
    end

    it 'calls the correct endpoint with default values' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies?"

      expect(trophies.title_trophies(np_communication_id: np_comm_id)).to eq(response)
      expect(request).to have_received(:get).with(path)
    end

    it 'derives service name for PS4 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies?npServiceName=trophy"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS4')

      expect(request).to have_received(:get).with(path)
    end

    it 'derives service name for PS5 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies?npServiceName=trophy2"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS5')

      expect(request).to have_received(:get).with(path)
    end

    it 'raises an error if both np_service_name and platform are provided' do
      expect do
        trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS4', np_service_name: 'trophy')
      end.to raise_error(ArgumentError, /Provide either np_service_name or platform, not both/)
    end

    it 'includes limit and offset when provided' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies?limit=10&offset=5"

      trophies.title_trophies(np_communication_id: np_comm_id, limit: 10, offset: 5)

      expect(request).to have_received(:get).with(path)
    end
  end
end
