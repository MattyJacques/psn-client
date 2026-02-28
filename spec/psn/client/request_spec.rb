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
    let(:captured_requests) { [] }

    before do
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |req|
        captured_requests << req
        response
      end
    end

    it 'makes a request with correct headers' do
      request_service.get('/test')

      expect(http).to have_received(:request)
      expect(captured_requests.last['Authorization']).to eq("Bearer #{access_token}")
      expect(captured_requests.last).to have_attributes(path: '/api/test', method: 'GET')
    end

    it 'parses the response' do
      expect(request_service.get('/test')).to eq({ 'key' => 'value' })
    end

    context 'when request fails' do
      let(:response) { instance_double(Net::HTTPNotFound, body: 'Not Found', code: '404', message: 'Not Found') }

      it 'raises an error with status code and message' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 404/)
      end
    end

    context 'when unauthorized' do
      let(:response) { instance_double(Net::HTTPUnauthorized, body: 'Unauthorized', code: '401', message: 'Unauthorized') }

      it 'raises an error' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 401/)
      end
    end

    context 'when server error occurs' do
      let(:response) { instance_double(Net::HTTPServerError, body: 'Internal Server Error', code: '500', message: 'Internal Server Error') }

      it 'raises an error' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 500/)
      end
    end
  end
end
