# frozen_string_literal: true

RSpec.describe PSN::Client do
  it 'has a version number' do
    expect(PSN::Client::VERSION).not_to be_nil
  end
end
