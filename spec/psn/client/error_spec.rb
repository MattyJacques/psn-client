# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Error do
  it 'defaults HTTP details to empty' do
    expect(described_class.new('boom')).to have_attributes(message: 'boom', status: nil, headers: {}, body: nil)
  end

  it 'is the parent of every gem error' do
    classes = [PSN::Client::AuthenticationError, PSN::Client::PrivacyError, PSN::Client::RateLimitError,
               PSN::Client::GraphQLError, PSN::Client::TransportError, PSN::Client::ParseError]
    expect(classes).to all(be < described_class)
  end

  describe PSN::Client::RateLimitError do
    def error_with(headers)
      PSN::Client::RateLimitError.new('slow down', status: 429, headers: headers)
    end

    let(:now) { Time.at(1_700_000_000) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    it 'reads X-RateLimit-Next-Available as a unix timestamp' do
      expect(error_with('x-ratelimit-next-available' => '1700000300').retry_at).to eq(Time.at(1_700_000_300))
    end

    it 'reads Retry-After in seconds' do
      expect(error_with('retry-after' => '120').retry_at).to eq(now + 120)
    end

    it 'reads Retry-After as an HTTP date' do
      expect(error_with('retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT').retry_at)
        .to eq(Time.utc(2015, 10, 21, 7, 28, 0))
    end

    it 'returns nil for an unparseable header' do
      expect(error_with('retry-after' => 'soon').retry_at).to be_nil
    end

    it 'returns nil without rate-limit headers' do
      expect(error_with({}).retry_at).to be_nil
    end
  end
end
