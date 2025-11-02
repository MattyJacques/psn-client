# frozen_string_literal: true

require 'spec_helper'
require 'psn/logger'
require 'stringio'

RSpec.describe 'Logger' do
  describe '.logger' do
    before do
      # ensure each example starts with a fresh cached value
      PSN.logger = nil
    end

    it 'allows setting a custom logger' do
      buffer = StringIO.new
      custom = Logger.new(buffer)
      PSN.logger = custom
      expect(PSN.logger).to equal(custom)
    end

    context 'when in a Rails environment' do
      it 'returns Rails.logger when Rails is defined' do
        buffer = StringIO.new
        rails_logger = Logger.new(buffer)
        stub_const('Rails', Module.new)
        allow(Rails).to receive(:logger).and_return(rails_logger)

        expect(PSN.logger).to equal(rails_logger)
      end
    end

    context 'when not in a Rails environment' do
      it 'returns a Logger by default' do
        hide_const('Rails')
        expect(PSN.logger).to be_a(Logger)
      end
    end
  end
end
