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
  end

  describe '#authenticate' do
    let(:auth) { described_class.new }
    let(:http) { instance_double(Net::HTTP) }
    let(:oauth_client) { instance_double(OAuth2::Client) }
    let(:auth_code_strategy) { instance_double(OAuth2::Strategy::AuthCode) }
    let(:access_token) { instance_double(OAuth2::AccessToken, token: 'ACCESS_TOKEN', expires_in: 600) }

    before do
      allow(ENV).to receive(:fetch).with('PSN_NPSSO', nil).and_return('test_npsso')
      allow(ENV).to receive(:fetch).with('PSN_CLIENT_ID', nil).and_return('test_client_id')
      allow(ENV).to receive(:fetch).with('PSN_BASIC_TOKEN', nil).and_return('test_basic_token')

      allow(OAuth2::Client).to receive(:new).and_return(oauth_client)
      allow(oauth_client).to receive(:auth_code).and_return(auth_code_strategy)
      allow(auth_code_strategy).to receive(:authorize_url).and_return('https://auth.url')

      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
    end

    context 'when authentication succeeds' do
      let(:response) { { 'location' => 'https://redirect.url?code=AUTH_CODE_123' } }

      before do
        allow(http).to receive(:request).and_return(response)
        allow(auth_code_strategy).to receive(:get_token).and_return(access_token)
      end

      it 'returns the access token' do
        expect(auth.authenticate).to eq('ACCESS_TOKEN')
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
      let(:response) { {} }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises an error' do
        expect { auth.authenticate }
          .to raise_error('Failed to fetch PSN auth code, location header missing')
      end

      it 'logs the error' do
        auth.authenticate
      rescue StandardError
        expect(logger).to have_received(:error)
          .with('Failed to fetch PSN auth code, location header missing')
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

      let(:response) do
        instance_double(
          Net::HTTPResponse,
          body: response_body
        )
      end

      before do
        allow(response).to receive(:[]).with('location').and_return(nil)
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises the error description from the response body' do
        expect { auth.authenticate }
          .to raise_error("Parameter 'client_id' is malformed")
      end

      it 'logs the error description from the response body' do
        auth.authenticate
      rescue StandardError
        expect(logger).to have_received(:error)
          .with("Parameter 'client_id' is malformed")
      end
    end

    context 'when the NPSSO cookie has expired (login_required error)' do
      let(:response) { { 'location' => 'https://redirect.url?state=abc&error=login_required' } }

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises an error indicating the NPSSO code has expired' do
        expect { auth.authenticate }
          .to raise_error('PSN authorisation failed, NPSSO code has expired')
      end

      it 'logs the error' do
        auth.authenticate
      rescue StandardError
        expect(logger).to have_received(:error)
          .with('PSN authorisation failed, NPSSO code has expired')
      end
    end

    context 'when an unknown error is returned' do
      let(:response) { { 'location' => 'https://redirect.url?state=abc&error=server_error' } }

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
        {
          'location' => 'https://redirect.url?state=abc&error=invalid_request&error_description=Parameter+client_id+is+malformed'
        }
      end

      before do
        allow(http).to receive(:request).and_return(response)
      end

      it 'raises the error description' do
        expect { auth.authenticate }
          .to raise_error('Parameter client_id is malformed')
      end
    end

    context 'when the authorization code contains special characters' do
      let(:response) { { 'location' => 'https://redirect.url?code=v3:ABC-123_test.foo/bar=' } }

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
end
