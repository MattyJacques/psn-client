# frozen_string_literal: true

RSpec.describe PSN::Client do
  describe 'VERSION' do
    it 'follows semantic versioning format' do
      expect(PSN::Client::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe PSN::Client::Error do
    it 'can be rescued as StandardError' do
      expect { raise described_class, 'test' }.to raise_error(StandardError)
    end

    it 'can be raised with a message' do
      expect { raise described_class, 'test error' }
        .to raise_error(described_class, 'test error')
    end
  end
end
