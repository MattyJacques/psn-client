# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Authenticating over HTTP', :integration do
  let(:authorize_url) { 'https://ca.account.sony.com/api/authz/v3/oauth/authorize' }
  let(:token_url) { 'https://ca.account.sony.com/api/authz/v3/oauth/token' }
  let(:summary_url) { "#{HTTPIntegration::MOBILE}/trophy/v1/users/me/trophySummary" }
  let(:redirect) { 'com.scee.psxandroid.scecompcall://redirect/?code=v3.auth-code&cid=00000000' }
  let(:credentials) { { npsso: 'npsso-abc', client_id: 'client-1', basic_token: 'basic-1' } }

  before do
    allow(PSN).to receive(:logger).and_return(Logger.new(File::NULL))
    stub_request(:get, authorize_url).with(query: hash_including({}))
                                     .to_return(status: 302, headers: { 'Location' => redirect })
    stub_request(:post, token_url).to_return(json_fixture('token'))
    stub_request(:get, summary_url).to_return(json_fixture('trophy_summary'))
  end

  it 'sends the NPSSO cookie and OAuth client to the authorize endpoint' do
    PSN::Client::Session.authenticate(**credentials)

    expect(a_request(:get, authorize_url).with(
             query: hash_including('client_id' => 'client-1', 'response_type' => 'code',
                                   'redirect_uri' => 'com.scee.psxandroid.scecompcall://redirect'),
             headers: { 'Cookie' => 'npsso=npsso-abc' }
           )).to have_been_made.once
  end

  it 'exchanges the code from the redirect for a token' do
    PSN::Client::Session.authenticate(**credentials)

    expect(a_request(:post, token_url).with(
             body: hash_including('code' => 'v3.auth-code', 'grant_type' => 'authorization_code',
                                  'token_format' => 'jwt'),
             headers: { 'Authorization' => 'Basic basic-1' }
           )).to have_been_made.once
  end

  it 'uses the token from the exchange as the Bearer token for API calls' do
    session = PSN::Client::Session.authenticate(**credentials)

    expect(session.trophies.trophy_summary).to include('trophyLevel' => 300)
    expect(a_request(:get, summary_url).with(headers: { 'Authorization' => 'Bearer fixture-access-token' }))
      .to have_been_made.once
  end

  it 'keeps the refresh token and its expiry on the session' do
    tokens = PSN::Client::Session.authenticate(**credentials).tokens

    expect(tokens.refresh_token).to eq('fixture-refresh-token')
    expect(tokens.refresh_token_expires_at).to be_within(5).of(Time.now + 863_999)
  end

  context 'with a saved refresh token' do
    let(:session) do
      PSN::Client::Session.from_refresh_token('saved-refresh', client_id: 'client-1', basic_token: 'basic-1')
    end

    it 'sends the refresh token grant to the token endpoint and skips the authorize step' do
      session

      expect(a_request(:post, token_url).with(
               body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => 'saved-refresh',
                                    'token_format' => 'jwt', 'scope' => 'psn:mobile.v2.core psn:clientapp'),
               headers: { 'Authorization' => 'Basic basic-1' }
             )).to have_been_made.once
      expect(a_request(:get, authorize_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'uses the refreshed token for API calls and keeps the refresh token' do
      expect(session.trophies.trophy_summary).to include('trophyLevel' => 300)
      expect(a_request(:get, summary_url).with(headers: { 'Authorization' => 'Bearer fixture-access-token' }))
        .to have_been_made.once
      expect(session.tokens.refresh_token).to eq('fixture-refresh-token')
    end

    context 'when the refresh token is no longer valid' do
      before do
        stub_request(:post, token_url).to_return(
          status: 400, headers: HTTPIntegration::JSON_HEADERS,
          body: '{"error":"invalid_grant","error_description":"Invalid refresh token","error_code":4159}'
        )
      end

      it 'raises AuthenticationError with the OAuth error code' do
        expect { session }
          .to raise_error(PSN::Client::AuthenticationError, /Invalid refresh token/) { |error|
            expect(error).to have_attributes(error_code: 'invalid_grant', status: 400)
          }
      end
    end
  end

  context 'when the NPSSO has expired' do
    let(:redirect) { 'com.scee.psxandroid.scecompcall://redirect/?error=login_required' }

    it 'raises AuthenticationError with the OAuth error code and the redirect response' do
      expect { PSN::Client::Session.authenticate(**credentials) }
        .to raise_error(PSN::Client::AuthenticationError, /NPSSO code has expired/) { |error|
          expect(error).to have_attributes(error_code: 'login_required', status: 302,
                                           headers: include('location' => redirect))
        }
    end

    it 'never requests a token' do
      expect { PSN::Client::Session.authenticate(**credentials) }.to raise_error(PSN::Client::AuthenticationError)
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  context 'when the token endpoint rejects the code' do
    before do
      stub_request(:post, token_url).to_return(
        status: 400, headers: HTTPIntegration::JSON_HEADERS,
        body: '{"error":"invalid_grant","error_description":"Invalid authorization code"}'
      )
    end

    it 'raises AuthenticationError carrying the token response' do
      expect { PSN::Client::Session.authenticate(**credentials) }
        .to raise_error(PSN::Client::AuthenticationError, /Invalid authorization code/) { |error|
          expect(error).to have_attributes(error_code: 'invalid_grant', status: 400, body: /invalid_grant/)
        }
    end
  end

  context 'when the token response is not JSON' do
    before do
      stub_request(:post, token_url).to_return(status: 200, headers: HTTPIntegration::JSON_HEADERS, body: '<html>')
    end

    it 'raises ParseError' do
      expect { PSN::Client::Session.authenticate(**credentials) }.to raise_error(PSN::Client::ParseError)
    end
  end
end
