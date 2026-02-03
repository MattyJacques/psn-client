#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'psn/client'

begin
  puts 'Authenticating...'
  token = PSN::Client::Auth.authenticate
  puts 'Authenticated!'

  trophies = PSN::Client::Trophies.new(token)
  puts "Fetching trophy titles for 'me'..."
  response = trophies.trophy_titles

  if response['trophyTitles']
    titles = response['trophyTitles']
    puts "Found #{titles.size} titles."
    puts "First title: #{titles.first['trophyTitleName']} (ID: #{titles.first['npCommunicationId']})" if titles.any?
  else
    puts "Unexpected response: #{response}"
  end
rescue StandardError => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.take(3)
end
