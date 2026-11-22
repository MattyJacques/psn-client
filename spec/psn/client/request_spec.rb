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

    it 'leaves a legacy path with its own query untouched' do
      request_service.get('/trophy?limit=1')
      expect(captured_requests.last.path).to eq('/api/trophy?limit=1')
    end

    it 'URL-encodes params' do
      request_service.get('/x', params: { 'fields' => 'a,b(c)', 'n' => 1 })
      expect(captured_requests.last.path).to eq('/api/x?fields=a%2Cb%28c%29&n=1')
    end

    it 'appends params to a path that already has a query' do
      request_service.get('/x?a=1', params: { 'b' => 2 })
      expect(captured_requests.last.path).to eq('/api/x?a=1&b=2')
    end

    it 'targets another host' do
      request_service.get('/userProfile/v1/users/abc/profile2', host: :community)
      expect(Net::HTTP).to have_received(:start).with('us-prof.np.community.playstation.net', 443, use_ssl: true)
      expect(captured_requests.last.path).to eq('/userProfile/v1/users/abc/profile2')
    end

    it 'raises KeyError for an unknown host' do
      expect { request_service.get('/x', host: :nope) }.to raise_error(KeyError)
    end

    it 'sends extra headers' do
      request_service.get('/x', headers: { 'apollographql-client-name' => 'oracle' })
      expect(captured_requests.last['apollographql-client-name']).to eq('oracle')
    end

    context 'when forbidden by access control' do
      let(:response) do
        instance_double(Net::HTTPForbidden, code: '403', message: 'Forbidden',
                                            body: '{"error":{"message":"Not permitted by access control"}}')
      end

      it 'raises PrivacyError' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::PrivacyError, /Request failed: 403/)
      end
    end

    context 'when forbidden with a string error mentioning privacy' do
      let(:response) do
        instance_double(Net::HTTPForbidden, code: '403', message: 'Forbidden', body: '{"error":"Privacy settings"}')
      end

      it 'raises PrivacyError' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::PrivacyError)
      end
    end

    context 'when forbidden with a non-JSON body' do
      let(:response) { instance_double(Net::HTTPForbidden, code: '403', message: 'Forbidden', body: '<html>') }

      it 'raises a plain Error' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error) do |e|
          expect(e).not_to be_a(PSN::Client::PrivacyError)
        end
      end
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
