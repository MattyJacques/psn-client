# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Tokens do
  subject(:tokens) do
    described_class.new(access_token: 'ACCESS', expires_at: expires_at, refresh_token: 'REFRESH',
                        refresh_token_expires_at: refresh_token_expires_at)
  end

  let(:now) { Time.at(1_800_000_000) }
  let(:expires_at) { now + 3_599 }
  let(:refresh_token_expires_at) { now + 863_999 }

  describe '#initialize' do
    it 'exposes the tokens and their expiry times' do
      expect(tokens).to have_attributes(access_token: 'ACCESS', expires_at: expires_at, refresh_token: 'REFRESH',
                                        refresh_token_expires_at: refresh_token_expires_at)
    end

    it 'needs only an access token' do
      expect(described_class.new(access_token: 'a'))
        .to have_attributes(access_token: 'a', expires_at: nil, refresh_token: nil, refresh_token_expires_at: nil)
    end

    it 'is frozen' do
      expect(tokens).to be_frozen
    end
  end

  describe '#expired?' do
    it 'is false before the access token expires' do
      expect(tokens).not_to be_expired(expires_at - 1)
    end

    it 'is true once the access token has expired' do
      expect(tokens).to be_expired(expires_at + 1)
    end

    it 'compares against the current time by default' do
      expect(described_class.new(access_token: 'a', expires_at: Time.now - 1)).to be_expired
    end

    context 'when the expiry is unknown' do
      let(:expires_at) { nil }

      it 'is false' do
        expect(tokens).not_to be_expired(now)
      end
    end
  end

  describe '#refresh_token_expired?' do
    it 'is false before the refresh token expires' do
      expect(tokens).not_to be_refresh_token_expired(refresh_token_expires_at - 1)
    end

    it 'is true once the refresh token has expired' do
      expect(tokens).to be_refresh_token_expired(refresh_token_expires_at + 1)
    end

    it 'compares against the current time by default' do
      expect(described_class.new(access_token: 'a', refresh_token_expires_at: Time.now - 1))
        .to be_refresh_token_expired
    end

    context 'when the expiry is unknown' do
      let(:refresh_token_expires_at) { nil }

      it 'is false' do
        expect(tokens).not_to be_refresh_token_expired(now)
      end
    end
  end

  describe '#inspect' do
    it 'shows the expiry times' do
      expect(tokens.inspect).to eq(
        "#<PSN::Client::Tokens expires_at=#{expires_at.inspect} " \
        "refresh_token_expires_at=#{refresh_token_expires_at.inspect}>"
      )
    end

    it 'leaves out the token values' do
      expect(tokens.inspect).not_to include('ACCESS', 'REFRESH')
    end
  end

  describe '#to_s' do
    it 'leaves out the token values, like inspect' do
      expect(tokens.to_s).to eq(tokens.inspect)
    end
  end

  describe '.from_oauth2' do
    subject(:tokens) { described_class.from_oauth2(oauth_token, now: now) }

    let(:oauth_token) do
      instance_double(OAuth2::AccessToken, token: 'ACCESS', refresh_token: refresh_token,
                                           expires_at: oauth_expires_at, params: params)
    end
    let(:refresh_token) { 'REFRESH' }
    let(:oauth_expires_at) { 1_800_003_599 }
    let(:params) { { 'refresh_token_expires_in' => 863_999 } }

    it 'takes both tokens from the response' do
      expect(tokens).to have_attributes(access_token: 'ACCESS', refresh_token: 'REFRESH')
    end

    it 'resolves both lifetimes to times' do
      expect(tokens).to have_attributes(expires_at: Time.at(1_800_003_599),
                                        refresh_token_expires_at: now + 863_999)
    end

    it 'measures the refresh token lifetime from the current time by default' do
      expect(described_class.from_oauth2(oauth_token).refresh_token_expires_at)
        .to be_within(5).of(Time.now + 863_999)
    end

    context 'when the response has no lifetimes' do
      let(:oauth_expires_at) { nil }
      let(:params) { {} }

      it 'leaves both expiry times unknown' do
        expect(tokens).to have_attributes(expires_at: nil, refresh_token_expires_at: nil)
      end

      it 'reports neither token as expired' do
        expect(tokens).to have_attributes(expired?: false, refresh_token_expired?: false)
      end
    end

    context 'when the refresh token lifetime is a numeric string' do
      let(:params) { { 'refresh_token_expires_in' => '863999' } }

      it 'still resolves it to a time' do
        expect(tokens.refresh_token_expires_at).to eq(now + 863_999)
      end
    end

    context 'when the refresh token lifetime is not numeric' do
      let(:params) { { 'refresh_token_expires_in' => 'soon' } }

      it 'leaves the refresh token expiry unknown' do
        expect(tokens.refresh_token_expires_at).to be_nil
      end
    end

    context 'with a fallback refresh token' do
      subject(:tokens) { described_class.from_oauth2(oauth_token, fallback_refresh_token: 'SAVED', now: now) }

      it 'prefers the refresh token from the response' do
        expect(tokens.refresh_token).to eq('REFRESH')
      end

      context 'when the response has no refresh token' do
        let(:refresh_token) { nil }

        it 'keeps the fallback' do
          expect(tokens.refresh_token).to eq('SAVED')
        end
      end

      context 'when the response has an empty refresh token' do
        let(:refresh_token) { '' }

        it 'keeps the fallback' do
          expect(tokens.refresh_token).to eq('SAVED')
        end
      end
    end
  end
end
