# frozen_string_literal: true

require 'spec_helper'
require 'psn/client/auth'

RSpec.describe PSN::Client::Auth do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }

  before do
    allow(PSN).to receive(:logger).and_return(logger)
  end

  describe '.authenticate' do
    let(:instance) { instance_double(described_class) }

    before do
      allow(described_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:authenticate).and_return('token')
    end

    it 'delegates to a new instance' do
      expect(described_class.authenticate).to eq('token')
    end

    it 'passes credentials to the new instance' do
      described_class.authenticate(npsso: 'n', client_id: 'c', basic_token: 'b')
      expect(described_class).to have_received(:new).with(npsso: 'n', client_id: 'c', basic_token: 'b')
    end

    it 'passes timeouts to the new instance' do
      described_class.authenticate(open_timeout: 2, read_timeout: 5, write_timeout: 7)
      expect(described_class).to have_received(:new).with(open_timeout: 2, read_timeout: 5, write_timeout: 7)
    end
  end

  describe '.tokens' do
    let(:tokens) { PSN::Client::Tokens.new(access_token: 'token') }
    let(:instance) { instance_double(described_class, tokens: tokens) }

    before do
      allow(described_class).to receive(:new).and_return(instance)
    end

    it 'delegates to a new instance built from the options' do
      expect(described_class.tokens(npsso: 'n')).to be(tokens)
      expect(described_class).to have_received(:new).with(npsso: 'n')
    end
  end

  describe '.refresh' do
    let(:tokens) { PSN::Client::Tokens.new(access_token: 'token') }
    let(:instance) { instance_double(described_class, refresh: tokens) }

    before do
      allow(described_class).to receive(:new).and_return(instance)
    end

    it 'refreshes on a new instance built from the options' do
      expect(described_class.refresh('r', client_id: 'c', read_timeout: 5)).to be(tokens)
      expect(described_class).to have_received(:new).with(client_id: 'c', read_timeout: 5)
      expect(instance).to have_received(:refresh).with('r')
    end
  end

  describe '#initialize' do
    it 'rejects unknown options' do
      expect { described_class.new(timeout: 5) }.to raise_error(ArgumentError, 'unknown keyword: :timeout')
    end
  end

  describe 'default credentials' do
    it 'defaults the client ID to the PlayStation app client' do
      expect(described_class::DEFAULT_CLIENT_ID).to eq('09515159-7237-4370-9b40-3806e67c0891')
    end

    it 'defaults the basic token to the base64 of the app client ID and secret' do
      expect(described_class::DEFAULT_BASIC_TOKEN.unpack1('m0'))
        .to eq("#{described_class::DEFAULT_CLIENT_ID}:ucPjka5tntB2KqsP")
    end

    context 'when PSN_CLIENT_ID is unset' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('PSN_CLIENT_ID', anything) { |_key, default| default }
        allow(OAuth2::Client).to receive(:new).and_call_original
      end

      it 'uses the default client ID' do
        described_class.new.send(:client)
        expect(OAuth2::Client).to have_received(:new).with(described_class::DEFAULT_CLIENT_ID, '', anything)
      end
    end
  end

  describe '#authenticate' do
    let(:auth) { described_class.new }
    let(:http) { instance_double(Net::HTTP) }
    let(:oauth_client) { instance_double(OAuth2::Client) }
    let(:auth_code_strategy) { instance_double(OAuth2::Strategy::AuthCode) }
    let(:access_token) do
      instance_double(OAuth2::AccessToken, token: 'ACCESS_TOKEN', expires_in: 600, refresh_token: 'REFRESH_TOKEN',
                                           expires_at: 1_800_003_599, params: { 'refresh_token_expires_in' => 863_999 })
    end

    before do
      allow(ENV).to receive(:fetch).with('PSN_NPSSO', nil).and_return('test_npsso')
      allow(ENV).to receive(:fetch).with('PSN_CLIENT_ID', described_class::DEFAULT_CLIENT_ID)
                                   .and_return('test_client_id')
      allow(ENV).to receive(:fetch).with('PSN_BASIC_TOKEN', described_class::DEFAULT_BASIC_TOKEN)
                                   .and_return('env_basic_token')

      allow(OAuth2::Client).to receive(:new).and_return(oauth_client)
      allow(oauth_client).to receive(:auth_code).and_return(auth_code_strategy)
      allow(auth_code_strategy).to receive(:authorize_url).and_return('https://auth.url')

      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
    end

    context 'when authentication succeeds' do
      let(:response) { http_response(302, '', 'Location' => 'https://redirect.url?code=AUTH_CODE_123') }

      before do
        allow(http).to receive(:request).and_return(response)
        allow(auth_code_strategy).to receive(:get_token).and_return(access_token)
      end

      it 'returns the access token' do
        expect(auth.authenticate).to eq('ACCESS_TOKEN')
      end

      it 'returns both tokens from #tokens' do
        expect(auth.tokens).to have_attributes(access_token: 'ACCESS_TOKEN', refresh_token: 'REFRESH_TOKEN',
                                               expires_at: Time.at(1_800_003_599))
      end

      it 'resolves the refresh token lifetime to a time' do
        expect(auth.tokens.refresh_token_expires_at).to be_within(5).of(Time.now + 863_999)
      end

      it 'logs the authentication process' do
        auth.authenticate

        expect(logger).to have_received(:info).with('Getting new PSN access token')
        expect(logger).to have_received(:info).with('Acquired new PSN access token')
      end

      it 'exchanges the authorization code for a token' do
        auth.authenticate

        expect(auth_code_strategy).to have_received(:get_token).with(
          'AUTH_CODE_123',
          hash_including(
            redirect_uri: 'com.scee.psxandroid.scecompcall://redirect',
            token_format: 'jwt'
          )
        )
      end

      it 'sends the basic token from the environment' do
        auth.authenticate

        expect(auth_code_strategy).to have_received(:get_token)
          .with('AUTH_CODE_123', hash_including(headers: { Authorization: 'Basic env_basic_token' }))
      end

      it 'creates the OAuth client with the client ID from the environment' do
        auth.authenticate
        expect(OAuth2::Client).to have_received(:new).with('test_client_id', '', anything)
      end

      context 'with timeouts' do
        let(:auth) { described_class.new(open_timeout: 2, read_timeout: 5, write_timeout: 7) }

        before do
          allow(http).to receive_messages('open_timeout=': nil, 'read_timeout=': nil, 'write_timeout=': nil)
          auth.authenticate
        end

        it 'applies them to the authorisation request' do
          expect(http).to have_received(:open_timeout=).with(2)
          expect(http).to have_received(:read_timeout=).with(5)
          expect(http).to have_received(:write_timeout=).with(7)
        end

        it 'applies them to the token exchange' do
          expect(OAuth2::Client).to have_received(:new).with(
            'test_client_id', '',
            hash_including(connection_opts: { request: { open_timeout: 2, read_timeout: 5, write_timeout: 7 } })
          )
        end
      end

      it 'leaves the token exchange timeouts at their defaults' do
        auth.authenticate
        expect(OAuth2::Client).to have_received(:new)
          .with('test_client_id', '', hash_including(connection_opts: { request: {} }))
      end

      context 'with explicit credentials' do
        let(:auth) { described_class.new(npsso: 'my_npsso', client_id: 'my_client', basic_token: 'my_basic') }

        it 'uses the client ID and basic token given' do
          auth.authenticate

          expect(OAuth2::Client).to have_received(:new).with('my_client', '', anything)
          expect(auth_code_strategy).to have_received(:get_token)
            .with('AUTH_CODE_123', hash_including(headers: { Authorization: 'Basic my_basic' }))
        end

        it 'uses the NPSSO given' do
          auth.authenticate
          expect(http).to have_received(:request) { |request| expect(request['Cookie']).to eq('npsso=my_npsso') }
        end

        it 'does not read the environment' do
          auth.authenticate
          expect(ENV).not_to have_received(:fetch)
        end
      end

      it 'sets the NPSSO cookie on the request' do
        auth.authenticate

        expect(http).to have_received(:request) do |request|
          expect(request['Cookie']).to eq('npsso=test_npsso')
        end
      end

      it 'uses SSL for the HTTP connection' do
        auth.authenticate

        expect(http).to have_received(:use_ssl=).with(true)
      end
    end

    context 'when the response has no location header' do
      let(:response) { http_response(200, 'not json') }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises AuthenticationError' do
        message = 'Failed to fetch PSN auth code, location header missing'
        expect { auth.authenticate }.to raise_error(PSN::Client::AuthenticationError, message) do |e|
          expect(e).to have_attributes(error_code: nil, status: 200, body: 'not json')
        end
      end

      it 'logs the error' do
        auth.authenticate
      rescue StandardError
        expect(logger).to have_received(:error)
          .with('Failed to fetch PSN auth code, location header missing')
      end
    end

    context 'when the authorisation request is rate limited' do
      before do
        allow(http).to receive(:request).and_return(http_response(429, '', 'Retry-After' => '120'))
      end

      it 'raises RateLimitError with the retry time' do
        expect { auth.authenticate }.to raise_error(PSN::Client::RateLimitError) do |e|
          expect(e).to have_attributes(status: 429, retry_at: be_a(Time))
        end
      end
    end

    context 'when the authorisation endpoint has a server error' do
      before do
        allow(http).to receive(:request).and_return(http_response(503, 'unavailable'))
      end

      it 'raises a plain Error rather than AuthenticationError' do
        expect { auth.authenticate }.to raise_error(PSN::Client::Error) do |e|
          expect(e).to be_an_instance_of(PSN::Client::Error)
          expect(e).to have_attributes(status: 503, body: 'unavailable')
        end
      end
    end

    context 'when the redirect location is not a valid URI' do
      let(:response) { http_response(302, '', 'Location' => 'https://redirect url?code=AUTH_CODE_123') }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises AuthenticationError with the response details' do
        expect { auth.authenticate }
          .to raise_error(PSN::Client::AuthenticationError, /PSN authorisation redirect was malformed/) do |e|
          expect(e.status).to eq(302)
          expect(e.cause).to be_a(URI::InvalidURIError)
        end
      end
    end

    context 'when the redirect query is not valid form encoding' do
      let(:response) { http_response(302, '', 'Location' => 'https://redirect.url?error_description=%ZZ') }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises AuthenticationError' do
        expect { auth.authenticate }
          .to raise_error(PSN::Client::AuthenticationError, /PSN authorisation redirect was malformed/)
      end
    end

    context 'when the response body contains an error description' do
      let(:response_body) do
        {
          error: 'invalid_request',
          error_code: 4099,
          error_description: "Parameter 'client_id' is malformed"
        }.to_json
      end

      let(:response) { http_response(400, response_body) }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises AuthenticationError with the error description and response details' do
        expect { auth.authenticate }
          .to raise_error(PSN::Client::AuthenticationError, "Parameter 'client_id' is malformed") do |e|
          expect(e).to have_attributes(error_code: 'invalid_request', status: 400, body: response_body)
        end
      end

      it 'logs the error description from the response body' do
        auth.authenticate
      rescue StandardError
        expect(logger).to have_received(:error)
          .with("Parameter 'client_id' is malformed")
      end
    end

    context 'when the NPSSO cookie has expired (login_required error)' do
      let(:response) { http_response(302, '', 'Location' => 'https://redirect.url?state=abc&error=login_required') }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises AuthenticationError indicating the NPSSO code has expired' do
        expect { auth.authenticate }
          .to raise_error(PSN::Client::AuthenticationError, 'PSN authorisation failed, NPSSO code has expired') do |e|
          expect(e).to have_attributes(error_code: 'login_required', status: 302)
          expect(e.headers).to include('location' => 'https://redirect.url?state=abc&error=login_required')
        end
      end

      it 'logs the error' do
        auth.authenticate
      rescue StandardError
        expect(logger).to have_received(:error)
          .with('PSN authorisation failed, NPSSO code has expired')
      end
    end

    context 'when an unknown error is returned' do
      let(:response) { http_response(302, '', 'Location' => 'https://redirect.url?state=abc&error=server_error') }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises an error with the error code' do
        expect { auth.authenticate }
          .to raise_error('Unhandled PSN auth error (server_error)')
      end
    end

    context 'when an error description is returned in the redirect URL' do
      let(:response) do
        http_response(302, '', 'Location' => 'https://redirect.url?state=abc&error=invalid_request&error_description=Parameter+client_id+is+malformed')
      end

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises the error description' do
        expect { auth.authenticate }
          .to raise_error('Parameter client_id is malformed')
      end
    end

    context 'when the authorisation request cannot connect' do
      before do
        allow(http).to receive(:request).and_raise(SocketError, 'getaddrinfo failed')
      end

      it 'raises TransportError wrapping the network error' do
        expect { auth.authenticate }
          .to raise_error(PSN::Client::TransportError, /SocketError: getaddrinfo failed/) do |e|
          expect(e.cause).to be_a(SocketError)
        end
        expect(logger).to have_received(:error).with(/PSN authorisation request failed/)
      end
    end

    context 'when the token exchange is rejected' do
      let(:token_response) do
        instance_double(OAuth2::Response, status: 400, headers: { 'Content-Type' => 'application/json' },
                                          body: '{"error":"invalid_grant"}',
                                          parsed: { 'error' => 'invalid_grant', 'error_description' => 'Bad code' })
      end

      before do
        allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
        allow(auth_code_strategy).to receive(:get_token).and_raise(OAuth2::Error.new(token_response))
      end

      it 'raises AuthenticationError with the OAuth details' do
        expect { auth.authenticate }.to raise_error(PSN::Client::AuthenticationError, /Bad code/) do |e|
          expect(e).to have_attributes(error_code: 'invalid_grant', status: 400, body: '{"error":"invalid_grant"}',
                                       headers: { 'content-type' => 'application/json' })
          expect(e.cause).to be_a(OAuth2::Error)
        end
      end
    end

    { 429 => PSN::Client::RateLimitError, 503 => PSN::Client::Error }.each do |status, error_class|
      context "when the token exchange answers HTTP #{status}" do
        let(:token_response) do
          instance_double(OAuth2::Response, status: status, headers: {}, body: 'try later', parsed: nil)
        end

        before do
          allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
          allow(auth_code_strategy).to receive(:get_token).and_raise(OAuth2::Error.new(token_response))
        end

        it "raises #{error_class} rather than AuthenticationError" do
          expect { auth.authenticate }.to raise_error(PSN::Client::Error, /PSN token exchange failed/) do |e|
            expect(e).to be_an_instance_of(error_class)
            expect(e).to have_attributes(status: status, body: 'try later')
          end
        end
      end
    end

    context 'when the token exchange is rejected without a response object' do
      before do
        allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
        allow(auth_code_strategy).to receive(:get_token)
          .and_raise(OAuth2::Error.new('error' => 'invalid_grant'))
      end

      it 'raises AuthenticationError without HTTP details' do
        expect { auth.authenticate }.to raise_error(PSN::Client::AuthenticationError) do |e|
          expect(e).to have_attributes(error_code: 'invalid_grant', status: nil)
        end
      end
    end

    context 'when the token response is malformed JSON' do
      before do
        allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
        allow(auth_code_strategy).to receive(:get_token)
          .and_raise(JSON::ParserError, %(unexpected token at '{"access_token":"ACCESS_TOKEN'))
      end

      it 'raises ParseError wrapping the JSON error' do
        expect { auth.authenticate }.to raise_error(PSN::Client::ParseError, /token response was not valid JSON/) do |e|
          expect(e.cause).to be_a(JSON::ParserError)
        end
      end

      it 'keeps the response body the JSON error quotes out of the message and the log' do
        expect { auth.authenticate }.to raise_error(PSN::Client::ParseError, 'PSN token response was not valid JSON')
        expect(logger).to have_received(:error).with('PSN token response was not valid JSON')
      end
    end

    context 'when the token request times out' do
      before do
        allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
        allow(auth_code_strategy).to receive(:get_token).and_raise(Faraday::TimeoutError)
      end

      it 'raises TransportError' do
        expect { auth.authenticate }.to raise_error(PSN::Client::TransportError, /PSN token request failed/) do |e|
          expect(e.cause).to be_a(Faraday::TimeoutError)
        end
      end
    end

    context 'when the token request fails with another Faraday error' do
      before do
        allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
        allow(auth_code_strategy).to receive(:get_token).and_raise(Faraday::Error, 'adapter failure')
      end

      it 'raises TransportError' do
        expect { auth.authenticate }.to raise_error(PSN::Client::TransportError, /adapter failure/) do |e|
          expect(e.cause).to be_a(Faraday::Error)
        end
      end
    end

    context 'when debug logging is on' do
      let(:debug_messages) { [] }
      let(:expires_in) { 600 }
      let(:access_token) do
        instance_double(OAuth2::AccessToken, token: 'ACCESS_TOKEN', expires_in: expires_in,
                                             refresh_token: 'REFRESH_TOKEN', expires_at: nil, params: {})
      end

      before do
        allow(http).to receive(:request).and_return(http_response(302, '', 'Location' => 'https://r.url?code=C'))
        allow(auth_code_strategy).to receive(:get_token).and_return(access_token)
        allow(logger).to receive(:debug) { |&block| debug_messages << block.call }
      end

      it 'logs the token lifetime in minutes' do
        auth.authenticate
        expect(debug_messages).to include('Fetched access token which expires in: 10 minutes')
      end

      context 'when the token response has no expires_in' do
        let(:expires_in) { nil }

        it 'still returns the token' do
          expect(auth.authenticate).to eq('ACCESS_TOKEN')
          expect(debug_messages).to include('Fetched access token which expires in: unknown minutes')
        end
      end
    end

    context 'when the authorization code contains special characters' do
      let(:response) { http_response(302, '', 'Location' => 'https://redirect.url?code=v3:ABC-123_test.foo/bar=') }

      before do
        allow(http).to receive(:request).and_return(response)
        allow(auth_code_strategy).to receive(:get_token).and_return(access_token)
      end

      it 'correctly extracts the code' do
        auth.authenticate

        expect(auth_code_strategy).to have_received(:get_token)
          .with('v3:ABC-123_test.foo/bar=', anything)
      end
    end
  end

  describe '#refresh' do
    let(:auth) { described_class.new }
    let(:oauth_client) { instance_double(OAuth2::Client) }
    let(:refreshed_token) { 'REFRESH_TOKEN' }
    let(:access_token) do
      instance_double(OAuth2::AccessToken, token: 'ACCESS_TOKEN', refresh_token: refreshed_token,
                                           expires_at: 1_800_003_599, params: { 'refresh_token_expires_in' => 863_999 })
    end

    before do
      allow(ENV).to receive(:fetch).with('PSN_NPSSO', anything)
      allow(ENV).to receive(:fetch).with('PSN_CLIENT_ID', described_class::DEFAULT_CLIENT_ID)
                                   .and_return('test_client_id')
      allow(ENV).to receive(:fetch).with('PSN_BASIC_TOKEN', described_class::DEFAULT_BASIC_TOKEN)
                                   .and_return('env_basic_token')

      allow(OAuth2::Client).to receive(:new).and_return(oauth_client)
      allow(oauth_client).to receive(:get_token).and_return(access_token)
      allow(Net::HTTP).to receive(:new)
    end

    it 'requests new tokens with the refresh token grant' do
      auth.refresh('SAVED')

      expect(oauth_client).to have_received(:get_token).with(
        { grant_type: 'refresh_token', refresh_token: 'SAVED', scope: 'psn:mobile.v2.core psn:clientapp',
          token_format: 'jwt', headers: { Authorization: 'Basic env_basic_token' } }
      )
    end

    it 'returns the new tokens' do
      expect(auth.refresh('SAVED')).to have_attributes(access_token: 'ACCESS_TOKEN', refresh_token: 'REFRESH_TOKEN',
                                                       expires_at: Time.at(1_800_003_599))
    end

    it 'resolves the refresh token lifetime to a time' do
      expect(auth.refresh('SAVED').refresh_token_expires_at).to be_within(5).of(Time.now + 863_999)
    end

    it 'logs the refresh' do
      auth.refresh('SAVED')

      expect(logger).to have_received(:info).with('Refreshing PSN access token')
      expect(logger).to have_received(:info).with('Refreshed PSN access token')
    end

    it 'does not need the NPSSO' do
      auth.refresh('SAVED')

      expect(ENV).not_to have_received(:fetch).with('PSN_NPSSO', anything)
      expect(Net::HTTP).not_to have_received(:new)
    end

    context 'with a real logger at debug level' do
      let(:log) { StringIO.new }
      let(:logger) { Logger.new(log, level: Logger::DEBUG) }

      it 'never logs a token' do
        auth.refresh('SAVED')

        expect(log.string).to include('Refreshed PSN access token')
        expect(log.string).not_to match(/SAVED|REFRESH_TOKEN|ACCESS_TOKEN/)
      end
    end

    context 'when the response has no refresh token' do
      let(:refreshed_token) { nil }

      it 'keeps the refresh token that was used' do
        expect(auth.refresh('SAVED').refresh_token).to eq('SAVED')
      end
    end

    context 'with explicit credentials' do
      let(:auth) { described_class.new(client_id: 'my_client', basic_token: 'my_basic') }

      it 'uses the client ID and basic token given' do
        auth.refresh('SAVED')

        expect(OAuth2::Client).to have_received(:new).with('my_client', '', anything)
        expect(oauth_client).to have_received(:get_token)
          .with(hash_including(headers: { Authorization: 'Basic my_basic' }))
      end
    end

    context 'with timeouts' do
      let(:auth) { described_class.new(read_timeout: 5) }

      it 'applies them to the token request' do
        auth.refresh('SAVED')

        expect(OAuth2::Client).to have_received(:new)
          .with('test_client_id', '', hash_including(connection_opts: { request: { read_timeout: 5 } }))
      end
    end

    [nil, '', "  \n", :saved].each do |blank|
      context "when the refresh token is #{blank.inspect}" do
        it 'raises ArgumentError without making a request' do
          expect { auth.refresh(blank) }.to raise_error(ArgumentError, 'a refresh token is required')
          expect(oauth_client).not_to have_received(:get_token)
        end
      end
    end

    context 'when the refresh token is rejected' do
      let(:token_response) do
        instance_double(OAuth2::Response, status: 400, headers: { 'Content-Type' => 'application/json' },
                                          body: '{"error":"invalid_grant"}',
                                          parsed: { 'error' => 'invalid_grant',
                                                    'error_description' => 'Invalid refresh token' })
      end

      before do
        allow(oauth_client).to receive(:get_token).and_raise(OAuth2::Error.new(token_response))
      end

      it 'raises AuthenticationError with the OAuth details' do
        expect { auth.refresh('SAVED') }
          .to raise_error(PSN::Client::AuthenticationError, 'PSN token refresh failed: Invalid refresh token') do |e|
          expect(e).to have_attributes(error_code: 'invalid_grant', status: 400)
          expect(e.cause).to be_a(OAuth2::Error)
        end
      end

      it 'logs the error' do
        expect { auth.refresh('SAVED') }.to raise_error(PSN::Client::AuthenticationError)
        expect(logger).to have_received(:error).with('PSN token refresh failed: Invalid refresh token')
      end
    end

    { 429 => PSN::Client::RateLimitError, 503 => PSN::Client::Error }.each do |status, error_class|
      context "when the token endpoint answers HTTP #{status}" do
        let(:token_response) do
          instance_double(OAuth2::Response, status: status, headers: {}, body: 'try later', parsed: nil)
        end

        before do
          allow(oauth_client).to receive(:get_token).and_raise(OAuth2::Error.new(token_response))
        end

        it "raises #{error_class} rather than AuthenticationError" do
          expect { auth.refresh('SAVED') }.to raise_error(PSN::Client::Error, /PSN token refresh failed/) do |e|
            expect(e).to be_an_instance_of(error_class)
            expect(e).to have_attributes(status: status, body: 'try later')
          end
        end
      end
    end

    context 'when the token request times out' do
      before do
        allow(oauth_client).to receive(:get_token).and_raise(Faraday::TimeoutError)
      end

      it 'raises TransportError' do
        expect { auth.refresh('SAVED') }
          .to raise_error(PSN::Client::TransportError, /PSN token request failed/) do |e|
          expect(e.cause).to be_a(Faraday::TimeoutError)
        end
      end
    end

    context 'when the token response is malformed JSON' do
      before do
        allow(oauth_client).to receive(:get_token)
          .and_raise(JSON::ParserError, %(unexpected token at '{"access_token":"ACCESS_TOKEN'))
      end

      it 'raises ParseError wrapping the JSON error' do
        expect { auth.refresh('SAVED') }
          .to raise_error(PSN::Client::ParseError, /token response was not valid JSON/) do |e|
          expect(e.cause).to be_a(JSON::ParserError)
        end
      end

      it 'keeps the response body the JSON error quotes out of the message and the log' do
        expect { auth.refresh('SAVED') }
          .to raise_error(PSN::Client::ParseError, 'PSN token response was not valid JSON')
        expect(logger).to have_received(:error).with('PSN token response was not valid JSON')
      end
    end
  end
end
