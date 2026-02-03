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
end
