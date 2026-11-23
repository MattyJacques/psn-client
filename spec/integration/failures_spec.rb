# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Failures over HTTP', :integration do
  let(:session) { PSN::Client::Session.new('access-token') }
  let(:summary_url) { "#{HTTPIntegration::MOBILE}/trophy/v1/users/me/trophySummary" }
  let(:graphql_url) { "#{HTTPIntegration::MOBILE}/graphql/v1/op" }

  describe 'error responses' do
    before { stub_request(:get, summary_url).to_return(response) }

    context 'with HTTP 401' do
      let(:response) do
        json_fixture('invalid_token', status: 401, headers: { 'WWW-Authenticate' => 'Bearer realm="PSN"' })
      end

      it 'raises AuthenticationError with the status, lowercased headers and raw body' do
        expect { session.trophies.trophy_summary }
          .to raise_error(PSN::Client::AuthenticationError, /Invalid token/) { |error|
            expect(error).to have_attributes(status: 401, body: fixture('invalid_token'),
                                             headers: include('www-authenticate' => 'Bearer realm="PSN"'))
          }
      end
    end

    context 'with HTTP 429' do
      let(:response) { { status: 429, headers: { 'X-RateLimit-Next-Available' => '1800000000' } } }

      it 'raises RateLimitError with the time requests are accepted again' do
        expect { session.trophies.trophy_summary }.to raise_error(PSN::Client::RateLimitError) { |error|
          expect(error).to have_attributes(status: 429, retry_at: Time.at(1_800_000_000))
        }
      end
    end

    context 'with HTTP 403 from access control' do
      let(:response) { json_fixture('access_denied', status: 403) }

      it 'raises PrivacyError' do
        expect { session.trophies.trophy_summary }.to raise_error(PSN::Client::PrivacyError) { |error|
          expect(error).to have_attributes(status: 403, body: fixture('access_denied'))
        }
      end
    end

    context 'with HTTP 503 and an HTML body' do
      let(:response) { { status: 503, body: '<html>Service Unavailable</html>' } }

      it 'raises a plain Error' do
        expect { session.trophies.trophy_summary }.to raise_error(PSN::Client::Error) { |error|
          expect(error).to be_an_instance_of(PSN::Client::Error)
          expect(error).to have_attributes(status: 503, body: '<html>Service Unavailable</html>')
        }
      end
    end
  end

  describe 'GraphQL failures' do
    before { stub_request(:get, graphql_url).with(query: hash_including({})).to_return(response) }

    context 'with errors in an HTTP 200 body' do
      let(:response) { json_fixture('graphql_errors') }

      it 'raises GraphQLError with the errors and partial data' do
        expect { session.account.library }
          .to raise_error(PSN::Client::GraphQLError, /Example resolver failure/) { |error|
            expect(error).to have_attributes(status: 200, data: { 'gameLibraryTitlesRetrieve' => nil },
                                             errors: [include('path' => ['gameLibraryTitlesRetrieve'])])
          }
      end
    end

    context 'with a persisted query Sony no longer accepts' do
      let(:response) { json_fixture('query_not_whitelisted', status: 400) }

      it 'raises Error with the response' do
        expect { session.account.library }.to raise_error(PSN::Client::Error, /not whitelisted/) { |error|
          expect(error).to have_attributes(status: 400, body: fixture('query_not_whitelisted'))
        }
      end
    end

    context 'with an empty HTTP 200 body' do
      let(:response) { { status: 200, body: '' } }

      it 'raises ParseError' do
        expect { session.account.library }.to raise_error(PSN::Client::ParseError, /empty/)
      end
    end
  end

  describe 'malformed responses' do
    before { stub_request(:get, summary_url).to_return(response) }

    context 'with an HTML body on HTTP 200' do
      let(:response) { { status: 200, body: '<html>Access Denied</html>' } }

      it 'raises ParseError keeping the body and the JSON error as cause' do
        expect { session.trophies.trophy_summary }.to raise_error(PSN::Client::ParseError) { |error|
          expect(error).to have_attributes(status: 200, body: '<html>Access Denied</html>',
                                           cause: an_instance_of(JSON::ParserError))
        }
      end
    end

    context 'with truncated JSON' do
      let(:response) { { status: 200, body: fixture('trophy_summary')[0, 40] } }

      it 'raises ParseError' do
        expect { session.trophies.trophy_summary }.to raise_error(PSN::Client::ParseError, /Invalid JSON/)
      end
    end

    context 'with an empty HTTP 200 body' do
      let(:response) { { status: 200, body: '' } }

      it 'returns nil' do
        expect(session.trophies.trophy_summary).to be_nil
      end
    end
  end

  describe 'network failures' do
    context 'when the connection times out' do
      before { stub_request(:get, summary_url).to_timeout }

      it 'raises TransportError with no response details' do
        expect { session.trophies.trophy_summary }.to raise_error(PSN::Client::TransportError) { |error|
          expect(error).to have_attributes(status: nil, headers: {}, body: nil,
                                           cause: a_kind_of(Timeout::Error))
        }
      end
    end

    context 'when the connection is refused' do
      before { stub_request(:get, summary_url).to_raise(Errno::ECONNREFUSED) }

      it 'raises TransportError naming the host' do
        expect { session.trophies.trophy_summary }
          .to raise_error(PSN::Client::TransportError, /m\.np\.playstation\.com.*ECONNREFUSED/)
      end
    end
  end
end
