# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Session do
  subject(:session) { described_class.new(request: request) }

  let(:request) { instance_double(PSN::Client::Request) }

  describe '.authenticate' do
    before do
      allow(PSN::Client::Auth).to receive(:authenticate).with(npsso: 'npsso').and_return('token')
      allow(PSN::Client::Request).to receive(:new).with('token').and_return(request)
    end

    it 'builds a session from the new access token' do
      expect(described_class.authenticate(npsso: 'npsso').request).to be(request)
    end

    context 'with timeouts' do
      let(:timeouts) { { open_timeout: 2, read_timeout: 5, write_timeout: 7 } }

      before do
        allow(PSN::Client::Auth).to receive(:authenticate).with(npsso: 'npsso', **timeouts).and_return('token')
        allow(PSN::Client::Request).to receive(:new).with('token', **timeouts).and_return(request)
      end

      it 'applies them to authentication' do
        described_class.authenticate(npsso: 'npsso', **timeouts)
        expect(PSN::Client::Auth).to have_received(:authenticate).with(npsso: 'npsso', **timeouts)
      end

      it 'applies them to the request' do
        described_class.authenticate(npsso: 'npsso', **timeouts)
        expect(PSN::Client::Request).to have_received(:new).with('token', **timeouts)
      end
    end
  end

  describe '#initialize' do
    before do
      allow(PSN::Client::Request).to receive(:new).with('token').and_return(request)
    end

    it 'builds a request from an access token' do
      expect(described_class.new('token').request).to be(request)
    end

    context 'with timeouts' do
      before do
        allow(PSN::Client::Request).to receive(:new).with('token', read_timeout: 5).and_return(request)
      end

      it 'passes them to the request' do
        expect(described_class.new('token', read_timeout: 5).request).to be(request)
      end
    end

    it 'rejects timeouts alongside an injected request' do
      expect { described_class.new(request: request, read_timeout: 5) }
        .to raise_error(ArgumentError, /injected request/)
    end

    it 'requires an access token or a request' do
      expect { described_class.new }.to raise_error(ArgumentError, /access token or a request/)
    end
  end

  describe 'resources' do
    before do
      allow(request).to receive(:get).and_return('ok')
    end

    it 'shares the request with trophies' do
      session.trophies.trophy_summary
      expect(request).to have_received(:get).with('/trophy/v1/users/me/trophySummary')
    end

    it 'shares the request with users' do
      session.users.profile_by_account_id(account_id: '1')
      expect(request).to have_received(:get)
    end

    it 'shares the request with account' do
      session.account.devices
      expect(request).to have_received(:get)
    end

    it 'memoizes each resource' do
      first = [session.trophies, session.users, session.account]
      expect([session.trophies, session.users, session.account]).to eq(first)
    end
  end
end
