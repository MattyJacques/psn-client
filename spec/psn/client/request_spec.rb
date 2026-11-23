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

    it 'identifies the gem in the User-Agent' do
      request_service.get('/test')

      expect(captured_requests.last['User-Agent']).to eq("psn-client/#{PSN::Client::VERSION}")
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
      let(:response) { http_response(403, '{"error":{"message":"Not permitted by access control"}}') }

      it 'raises PrivacyError with the response details' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::PrivacyError, /Request failed: 403/) do |e|
          expect(e).to have_attributes(status: 403, body: '{"error":{"message":"Not permitted by access control"}}')
        end
      end
    end

    context 'when forbidden with a string error mentioning privacy' do
      let(:response) { http_response(403, '{"error":"Privacy settings"}') }

      it 'raises PrivacyError' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::PrivacyError)
      end
    end

    [['a non-JSON body', '<html>'], ['an unrelated JSON error', '{"error":{"message":"Insufficient scope"}}'],
     ['a JSON null body', 'null'], ['a non-Hash, non-String error', '{"error":42}']].each do |description, body|
      context "when forbidden with #{description}" do
        let(:response) { http_response(403, body) }

        it 'raises a plain Error' do
          expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 403/) do |e|
            expect(e.class).to eq(PSN::Client::Error)
          end
        end
      end
    end

    context 'when request fails' do
      let(:response) { http_response(404, 'Not Found', 'X-Trace' => 'abc') }

      it 'raises a plain Error carrying status, headers and body' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 404/) do |e|
          expect(e.class).to eq(PSN::Client::Error)
          expect(e).to have_attributes(status: 404, body: 'Not Found', headers: include('x-trace' => 'abc'))
        end
      end
    end

    context 'when unauthorized' do
      let(:response) { http_response(401, 'Unauthorized') }

      it 'raises AuthenticationError' do
        expect { request_service.get('/test') }
          .to raise_error(PSN::Client::AuthenticationError, /Request failed: 401/) do |e|
          expect(e.status).to eq(401)
        end
      end
    end

    context 'when rate limited' do
      let(:response) { http_response(429, '', 'X-RateLimit-Next-Available' => '1800000000') }

      it 'raises RateLimitError with the time requests resume' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::RateLimitError) do |e|
          expect(e).to have_attributes(status: 429, retry_at: Time.at(1_800_000_000))
        end
      end
    end

    context 'when server error occurs' do
      let(:response) { http_response(500, 'Internal Server Error') }

      it 'raises an error' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::Error, /Request failed: 500/)
      end
    end

    context 'when a successful response is not JSON' do
      let(:response) { http_response(200, '<html>') }

      it 'raises ParseError wrapping the JSON error' do
        expect { request_service.get('/test') }.to raise_error(PSN::Client::ParseError) do |e|
          expect(e).to have_attributes(status: 200, body: '<html>')
          expect(e.cause).to be_a(JSON::ParserError)
        end
      end
    end
  end

  describe 'transport failures' do
    before do
      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout, 'execution expired')
    end

    it 'raises TransportError wrapping the network error' do
      expect { request_service.get('/test') }
        .to raise_error(PSN::Client::TransportError, /m\.np\.playstation\.com.*Net::OpenTimeout/) do |e|
        expect(e.cause).to be_a(Net::OpenTimeout)
        expect(e.status).to be_nil
      end
    end
  end

  describe '#post' do
    let(:captured_requests) { [] }

    before do
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |req|
        captured_requests << req
        response
      end
    end

    it 'sends a JSON body' do
      request_service.post('/search/v1/universalSearch', { 'searchTerm' => 'abc' })
      req = captured_requests.last
      expect(req).to have_attributes(method: 'POST', path: '/api/search/v1/universalSearch',
                                     body: '{"searchTerm":"abc"}')
      expect(req['Content-Type']).to eq('application/json')
    end

    it 'sends the bearer token and extra headers' do
      request_service.post('/x', {}, headers: { 'X-Extra' => 'y' })
      expect(captured_requests.last['Authorization']).to eq("Bearer #{access_token}")
      expect(captured_requests.last['X-Extra']).to eq('y')
    end

    it 'parses the response' do
      expect(request_service.post('/x', {})).to eq({ 'key' => 'value' })
    end
  end

  describe '#graphql' do
    let(:captured_requests) { [] }

    before do
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |req|
        captured_requests << req
        response
      end
    end

    it 'encodes a persisted query' do
      request_service.graphql('getUserGameList', { 'limit' => 1 }, 'abc123')
      query = URI.decode_www_form(URI(captured_requests.last.path).query).to_h
      expect(query).to eq('operationName' => 'getUserGameList', 'variables' => '{"limit":1}',
                          'extensions' => '{"persistedQuery":{"version":1,"sha256Hash":"abc123"}}')
      expect(captured_requests.last['Apollo-Require-Preflight']).to eq('true')
    end

    it 'uses the web host' do
      request_service.graphql('op', {}, 'h', host: :web)
      expect(Net::HTTP).to have_received(:start).with('web.np.playstation.com', 443, use_ssl: true)
      expect(URI(captured_requests.last.path).path).to eq('/api/graphql/v1/op')
    end

    it 'merges extra headers' do
      request_service.graphql('op', {}, 'h', headers: { 'X-Extra' => 'y' })
      expect(captured_requests.last['X-Extra']).to eq('y')
      expect(captured_requests.last['Apollo-Require-Preflight']).to eq('true')
    end

    context 'when the body carries GraphQL errors' do
      let(:response) do
        res = Net::HTTPSuccess.new(1.1, '200', 'OK')
        allow(res).to receive(:body).and_return('{"errors":[{"message":"bad"},{"message":"worse"}]}')
        res
      end

      it 'raises GraphQLError' do
        expect { request_service.graphql('op', {}, 'h') }
          .to raise_error(PSN::Client::GraphQLError, 'PSN GraphQL error: bad; worse')
      end
    end

    context 'when GraphQL errors come with partial data' do
      let(:response) { http_response(200, '{"data":{"a":1},"errors":[{"message":"bad","path":["b"]}]}') }

      it 'keeps the errors, partial data and status' do
        expect { request_service.graphql('op', {}, 'h') }.to raise_error(PSN::Client::GraphQLError) do |e|
          expect(e).to have_attributes(errors: [{ 'message' => 'bad', 'path' => ['b'] }],
                                       data: { 'a' => 1 }, status: 200)
        end
      end
    end

    context 'when an error has no message' do
      let(:response) do
        res = Net::HTTPSuccess.new(1.1, '200', 'OK')
        allow(res).to receive(:body).and_return('{"errors":[{"message":"bad"},{}]}')
        res
      end

      it 'omits the empty segment' do
        expect { request_service.graphql('op', {}, 'h') }
          .to raise_error(PSN::Client::Error, 'PSN GraphQL error: bad')
      end
    end

    context 'when errors is empty' do
      let(:response) do
        res = Net::HTTPSuccess.new(1.1, '200', 'OK')
        allow(res).to receive(:body).and_return('{"data":{},"errors":[]}')
        res
      end

      it 'returns the body' do
        expect(request_service.graphql('op', {}, 'h')).to eq('data' => {}, 'errors' => [])
      end
    end
  end
end
