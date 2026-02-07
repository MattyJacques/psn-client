# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Request do
  subject(:request_service) { described_class.new(access_token) }

  let(:access_token) { 'access_token' }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) do
    res = Net::HTTPSuccess.new(1.1, '200', 'OK')
    allow(res).to receive(:body).and_return('{"key":"value"}')
    res
  end

  describe '#get' do
    before do
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)
    end

    it 'makes a request with correct headers' do
      request_service.get('/test')

      expect(http).to have_received(:request) do |req|
        expect(req['Authorization']).to eq("Bearer #{access_token}")
        expect(req).to have_attributes(path: '/api/test', method: 'GET')
      end
    end

    it 'parses the response' do
      expect(request_service.get('/test')).to eq({ 'key' => 'value' })
    end

    context 'when request fails' do
      let(:response) { instance_double(Net::HTTPNotFound, body: 'Not Found', code: '404', message: 'Not Found') }

      it 'raises an error' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 404/)
      end
    end
  end
end
