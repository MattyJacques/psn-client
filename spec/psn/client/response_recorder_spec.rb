# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PSN::Client::ResponseRecorder do
  let(:recorded) { [] }
  let(:connection) do
    Faraday.new do |builder|
      builder.use(described_class, ->(response) { recorded << response })
      builder.adapter(:test) { |stub| stub.post('/token') { [200, { 'X-Trace' => 't1' }, '{bad'] } }
    end
  end

  it 'passes the completed response to the callback' do
    response = connection.post('/token')

    expect(recorded).to eq([response])
    expect(recorded.first).to have_attributes(status: 200, body: '{bad')
  end
end
