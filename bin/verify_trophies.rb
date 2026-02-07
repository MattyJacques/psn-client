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

    if titles.any?
      title = titles.first
      puts "First title: #{title['trophyTitleName']} (ID: #{title['npCommunicationId']})"

      service_name = title['npServiceName'] || 'trophy'
      puts "Fetching trophies for '#{title['trophyTitleName']}' (Service: #{service_name})..."

      title_trophies = trophies.title_trophies(
        np_communication_id: title['npCommunicationId'],
        np_service_name: service_name
      )

      if title_trophies['trophies']
        puts "Found #{title_trophies['trophies'].size} trophies."
        first_trophy = title_trophies['trophies'].first
        puts "First trophy: #{first_trophy['trophyName']} (ID: #{first_trophy['trophyId']})" if first_trophy
      else
        puts "Unexpected response for title trophies: #{title_trophies}"
      end
    end
  else
    puts "Unexpected response: #{response}"
  end
rescue StandardError => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.take(3)
end
