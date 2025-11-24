# frozen_string_literal: true

require 'spec_helper'
require 'psn/client/auth'

RSpec.describe PSN::Client::Auth do
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
    let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }
    let(:fake_token) { instance_double(OAuth2::AccessToken, token: 'ACCESS', expires_in: 600) }

    before do
      allow(PSN).to receive(:logger).and_return(logger)
      allow(auth).to receive(:fetch_auth_code).and_return('CODE123')
      allow(auth).to receive(:fetch_token).with('CODE123').and_return(fake_token)
      allow(logger).to receive(:debug)
    end

    it 'fetches an auth code, exchanges it for a token and returns the token' do
      expect(logger).to receive(:info).with('Getting new PSN access token')
      expect(logger).to receive(:info).with('Acquired new PSN access token')

      expect(auth.authenticate).to eq('ACCESS')
    end
  end
end
