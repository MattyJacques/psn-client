# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::Trophies do
  subject(:trophies) { described_class.new(request: request) }

  let(:request) { instance_double(PSN::Client::Request) }

  describe '#trophy_titles' do
    let(:response) { { 'trophyTitles' => [] } }

    before do
      allow(request).to receive(:get).and_return(response)
    end

    it 'requests the maximum page by default' do
      expect(trophies.trophy_titles).to eq(response)
      expect(request).to have_received(:get)
        .with('/trophy/v1/users/me/trophyTitles', params: { 'limit' => 800, 'offset' => 0 })
    end

    it 'passes parameters correctly' do
      trophies.trophy_titles(user_id: '12345', limit: 10, offset: 5)

      expect(request).to have_received(:get)
        .with('/trophy/v1/users/12345/trophyTitles', params: { 'limit' => 10, 'offset' => 5 })
    end

    it 'rejects a limit above the maximum' do
      expect { trophies.trophy_titles(limit: 801) }
        .to raise_error(ArgumentError, 'limit must be an Integer between 1 and 800, got 801')
    end

    it 'rejects a limit below 1 or not an Integer' do
      [0, -1, 1.5, '5', nil].each do |bad|
        expect { trophies.trophy_titles(limit: bad) }.to raise_error(ArgumentError, /limit must be an Integer/)
      end
    end

    it 'rejects a negative or non-Integer offset' do
      [-1, 1.5, '0', nil].each do |bad|
        expect { trophies.trophy_titles(offset: bad) }
          .to raise_error(ArgumentError, /offset must be an Integer at least 0/)
      end
    end

    it 'accepts an Integer user_id' do
      expect { trophies.trophy_titles(user_id: 12_345) }.not_to raise_error
    end

    it 'rejects user IDs that are not "me" or numeric' do
      ['example_user', '1/../x', '1?limit=999', "1\n", '', nil].each do |bad|
        expect { trophies.trophy_titles(user_id: bad) }.to raise_error(ArgumentError, /invalid PSN user ID/)
      end
    end
  end

  describe '#trophy_summary' do
    let(:response) do
      {
        'accountId' => '0000000000000000000',
        'trophyLevel' => 437,
        'progress' => 40,
        'earnedTrophies' => { 'bronze' => 6212, 'silver' => 1450, 'gold' => 525, 'platinum' => 55 }
      }
    end

    before do
      allow(request).to receive(:get).and_return(response)
    end

    it 'calls the correct endpoint with default values' do
      expect(trophies.trophy_summary).to eq(response)
      expect(request).to have_received(:get).with('/trophy/v1/users/me/trophySummary')
    end

    context 'with a custom user_id' do
      it 'passes the user_id correctly' do
        trophies.trophy_summary(user_id: '12345')

        expect(request).to have_received(:get).with('/trophy/v1/users/12345/trophySummary')
      end
    end

    it 'accepts an Integer user_id' do
      expect { trophies.trophy_summary(user_id: 12_345) }.not_to raise_error
    end

    it 'rejects user IDs that are not "me" or numeric' do
      ['example_user', '1/../x', '1?limit=999', "1\n", '', nil].each do |bad|
        expect { trophies.trophy_summary(user_id: bad) }.to raise_error(ArgumentError, /invalid PSN user ID/)
      end
    end
  end

  describe '#title_trophy_groups' do
    let(:response) { { 'trophyGroups' => [] } }
    let(:np_comm_id) { 'NPWR12345_00' }

    before do
      allow(request).to receive(:get).and_return(response)
    end

    it 'calls the correct endpoint with default values' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups"

      expect(trophies.title_trophy_groups(np_communication_id: np_comm_id)).to eq(response)
      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'accepts an explicit service name' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.title_trophy_groups(np_communication_id: np_comm_id, np_service_name: 'trophy')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PS4 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.title_trophy_groups(np_communication_id: np_comm_id, platform: 'PS4')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PS5 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.title_trophy_groups(np_communication_id: np_comm_id, platform: 'PS5')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy2' })
    end

    it 'raises an error if both np_service_name and platform are provided' do
      expect do
        trophies.title_trophy_groups(np_communication_id: np_comm_id, platform: 'PS4', np_service_name: 'trophy')
      end.to raise_error(ArgumentError, /Provide either np_service_name or platform, not both/)
    end

    it 'rejects malformed np_communication_ids' do
      ['npwr12345_00', 'NPWR1234_00', 'NPWR12345_00/../x', 'NPWR12345_00?x=1', '', nil].each do |bad|
        expect { trophies.title_trophy_groups(np_communication_id: bad) }
          .to raise_error(ArgumentError, /invalid NP communication ID/)
      end
    end
  end

  describe '#earned_trophy_groups' do
    let(:response) { { 'trophyGroups' => [] } }
    let(:np_comm_id) { 'NPWR12345_00' }

    before do
      allow(request).to receive(:get).and_return(response)
    end

    it 'calls the correct endpoint with default values' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups"

      expect(trophies.earned_trophy_groups(np_communication_id: np_comm_id)).to eq(response)
      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'accepts a custom user_id' do
      path = "/trophy/v1/users/12345/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.earned_trophy_groups(user_id: '12345', np_communication_id: np_comm_id)

      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'accepts an explicit service name' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.earned_trophy_groups(np_communication_id: np_comm_id, np_service_name: 'trophy')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PS4 platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.earned_trophy_groups(np_communication_id: np_comm_id, platform: 'PS4')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PS5 platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups"

      trophies.earned_trophy_groups(np_communication_id: np_comm_id, platform: 'PS5')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy2' })
    end

    it 'raises an error if both np_service_name and platform are provided' do
      expect do
        trophies.earned_trophy_groups(np_communication_id: np_comm_id, platform: 'PS4', np_service_name: 'trophy')
      end.to raise_error(ArgumentError, /Provide either np_service_name or platform, not both/)
    end

    it 'rejects malformed np_communication_ids' do
      ['npwr12345_00', 'NPWR1234_00', 'NPWR12345_00/../x', 'NPWR12345_00?x=1', '', nil].each do |bad|
        expect { trophies.earned_trophy_groups(np_communication_id: bad) }
          .to raise_error(ArgumentError, /invalid NP communication ID/)
      end
    end

    it 'accepts an Integer user_id' do
      expect { trophies.earned_trophy_groups(np_communication_id: np_comm_id, user_id: 12_345) }.not_to raise_error
    end

    it 'rejects user IDs that are not "me" or numeric' do
      ['example_user', '1/../x', '1?limit=999', "1\n", '', nil].each do |bad|
        expect { trophies.earned_trophy_groups(np_communication_id: np_comm_id, user_id: bad) }
          .to raise_error(ArgumentError, /invalid PSN user ID/)
      end
    end
  end

  describe '#title_trophies' do
    let(:response) { { 'trophies' => [] } }
    let(:np_comm_id) { 'NPWR12345_00' }

    before do
      allow(request).to receive(:get).and_return(response)
    end

    it 'calls the correct endpoint with default values' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      expect(trophies.title_trophies(np_communication_id: np_comm_id)).to eq(response)
      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'derives service name for PS4 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS4')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PS5 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS5')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy2' })
    end

    it 'derives service name for PS3 platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS3')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PSVita platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PSVita')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PC platform' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PC')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy2' })
    end

    it 'accepts a custom trophy_group_id' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/001/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, trophy_group_id: '001')

      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'raises an error if both np_service_name and platform are provided' do
      expect do
        trophies.title_trophies(np_communication_id: np_comm_id, platform: 'PS4', np_service_name: 'trophy')
      end.to raise_error(ArgumentError, /Provide either np_service_name or platform, not both/)
    end

    it 'includes limit and offset when provided' do
      path = "/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.title_trophies(np_communication_id: np_comm_id, limit: 10, offset: 5)

      expect(request).to have_received(:get).with(path, params: { 'limit' => 10, 'offset' => 5 })
    end

    it 'sends an offset without a limit' do
      trophies.title_trophies(np_communication_id: np_comm_id, offset: 5)

      expect(request).to have_received(:get).with(anything, params: { 'offset' => 5 })
    end

    it 'sets no upper bound on limit' do
      trophies.title_trophies(np_communication_id: np_comm_id, limit: 100_000)

      expect(request).to have_received(:get).with(anything, params: { 'limit' => 100_000 })
    end

    it 'rejects a limit below 1 or not an Integer' do
      [0, -1, 1.5, '5'].each do |bad|
        expect { trophies.title_trophies(np_communication_id: np_comm_id, limit: bad) }
          .to raise_error(ArgumentError, /limit must be an Integer at least 1/)
      end
    end

    it 'rejects a negative or non-Integer offset' do
      [-1, 1.5, '0'].each do |bad|
        expect { trophies.title_trophies(np_communication_id: np_comm_id, offset: bad) }
          .to raise_error(ArgumentError, /offset must be an Integer at least 0/)
      end
    end

    it 'rejects unknown keywords' do
      expect { trophies.title_trophies(np_communication_id: np_comm_id, limt: 10) }
        .to raise_error(ArgumentError, /unknown keyword/)
    end

    it 'rejects malformed np_communication_ids' do
      ['npwr12345_00', 'NPWR1234_00', 'NPWR12345_00/../x', 'NPWR12345_00?x=1', '', nil].each do |bad|
        expect { trophies.title_trophies(np_communication_id: bad) }
          .to raise_error(ArgumentError, /invalid NP communication ID/)
      end
    end

    it 'accepts the default trophy group' do
      expect { trophies.title_trophies(np_communication_id: np_comm_id, trophy_group_id: 'default') }.not_to raise_error
    end

    it 'rejects malformed trophy_group_ids' do
      ['ALL', '1', '0001', 'all/../x', '001?x=1', '', nil].each do |bad|
        expect { trophies.title_trophies(np_communication_id: np_comm_id, trophy_group_id: bad) }
          .to raise_error(ArgumentError, /invalid trophy group ID/)
      end
    end
  end

  describe '#earned_trophies' do
    let(:response) { { 'trophies' => [] } }
    let(:np_comm_id) { 'NPWR12345_00' }

    before do
      allow(request).to receive(:get).and_return(response)
    end

    it 'calls the correct endpoint with default values' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      expect(trophies.earned_trophies(np_communication_id: np_comm_id)).to eq(response)
      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'accepts a custom user_id' do
      path = "/trophy/v1/users/12345/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(user_id: '12345', np_communication_id: np_comm_id)

      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'derives service name for PS4 platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, platform: 'PS4')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PS5 platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, platform: 'PS5')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy2' })
    end

    it 'derives service name for PS3 platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, platform: 'PS3')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PSVita platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, platform: 'PSVita')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy' })
    end

    it 'derives service name for PC platform' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, platform: 'PC')

      expect(request).to have_received(:get).with(path, params: { 'npServiceName' => 'trophy2' })
    end

    it 'accepts a custom trophy_group_id' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/001/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, trophy_group_id: '001')

      expect(request).to have_received(:get).with(path, params: {})
    end

    it 'raises an error if both np_service_name and platform are provided' do
      expect do
        trophies.earned_trophies(np_communication_id: np_comm_id, platform: 'PS4', np_service_name: 'trophy')
      end.to raise_error(ArgumentError, /Provide either np_service_name or platform, not both/)
    end

    it 'includes limit and offset when provided' do
      path = "/trophy/v1/users/me/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"

      trophies.earned_trophies(np_communication_id: np_comm_id, limit: 10, offset: 5)

      expect(request).to have_received(:get).with(path, params: { 'limit' => 10, 'offset' => 5 })
    end

    it 'sends an offset without a limit' do
      trophies.earned_trophies(np_communication_id: np_comm_id, offset: 5)

      expect(request).to have_received(:get).with(anything, params: { 'offset' => 5 })
    end

    it 'sets no upper bound on limit' do
      trophies.earned_trophies(np_communication_id: np_comm_id, limit: 100_000)

      expect(request).to have_received(:get).with(anything, params: { 'limit' => 100_000 })
    end

    it 'rejects a limit below 1 or not an Integer' do
      [0, -1, 1.5, '5'].each do |bad|
        expect { trophies.earned_trophies(np_communication_id: np_comm_id, limit: bad) }
          .to raise_error(ArgumentError, /limit must be an Integer at least 1/)
      end
    end

    it 'rejects a negative or non-Integer offset' do
      [-1, 1.5, '0'].each do |bad|
        expect { trophies.earned_trophies(np_communication_id: np_comm_id, offset: bad) }
          .to raise_error(ArgumentError, /offset must be an Integer at least 0/)
      end
    end

    it 'rejects unknown keywords' do
      expect { trophies.earned_trophies(np_communication_id: np_comm_id, limt: 10) }
        .to raise_error(ArgumentError, /unknown keyword/)
    end

    it 'rejects malformed np_communication_ids' do
      ['npwr12345_00', 'NPWR1234_00', 'NPWR12345_00/../x', 'NPWR12345_00?x=1', '', nil].each do |bad|
        expect { trophies.earned_trophies(np_communication_id: bad) }
          .to raise_error(ArgumentError, /invalid NP communication ID/)
      end
    end

    it 'accepts the default trophy group' do
      expect { trophies.earned_trophies(np_communication_id: np_comm_id, trophy_group_id: 'default') }
        .not_to raise_error
    end

    it 'rejects malformed trophy_group_ids' do
      ['ALL', '1', '0001', 'all/../x', '001?x=1', '', nil].each do |bad|
        expect { trophies.earned_trophies(np_communication_id: np_comm_id, trophy_group_id: bad) }
          .to raise_error(ArgumentError, /invalid trophy group ID/)
      end
    end

    it 'accepts an Integer user_id' do
      expect { trophies.earned_trophies(np_communication_id: np_comm_id, user_id: 12_345) }.not_to raise_error
    end

    it 'rejects user IDs that are not "me" or numeric' do
      ['example_user', '1/../x', '1?limit=999', "1\n", '', nil].each do |bad|
        expect { trophies.earned_trophies(np_communication_id: np_comm_id, user_id: bad) }
          .to raise_error(ArgumentError, /invalid PSN user ID/)
      end
    end
  end

  describe '#initialize' do
    subject(:from_token) { described_class.new('access_token') }

    before do
      allow(PSN::Client::Request).to receive(:new).with('access_token').and_return(request)
      allow(request).to receive(:get).and_return('ok')
    end

    it 'builds a Request from an access token' do
      expect(from_token.trophy_summary).to eq('ok')
      expect(request).to have_received(:get)
        .with('/trophy/v1/users/me/trophySummary')
    end

    it 'requires an access token or a request' do
      expect { described_class.new }.to raise_error(ArgumentError, /access token or a request/)
    end
  end
end
