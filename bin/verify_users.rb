#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'debug'
require 'psn/client'

# Labels of failed checks; the script exits nonzero if any are recorded.
@failures = []

# Runs one check, printing its summary or the error without stopping the rest.
def check(label)
  result = yield
  puts "#{label}: #{result}"
rescue StandardError => e
  @failures << label
  puts "#{label}: FAILED: #{e.class}: #{e.message}"
  nil
end

puts 'Authenticating...'
token = PSN::Client::Auth.authenticate
puts 'Authenticated!'

users = PSN::Client::Users.new(token)
account = PSN::Client::Account.new(token)
online_id = nil
account_id = nil

check('Account#summary') do
  profile = account.summary.dig('data', 'oracleUserProfileRetrieve')
  online_id = profile['onlineId']
  account_id = profile['accountId']
  "online ID #{online_id}, account ID #{account_id}"
end

if online_id
  check('Users#search') do
    # Search leaves out the signed-in account, so search a prefix of its online ID.
    results = users.search(online_id[0, 4]).dig('data', 'universalContextSearch', 'results') || []
    social = results.find { |r| r['domain'] == 'SocialAllAccounts' } || {}
    "#{(social['searchResults'] || []).size} results"
  end
  check('Users#account_id') do
    found = users.account_id(online_id)
    raise PSN::Client::Error, "#{found} does not match summary account ID #{account_id}" if found != account_id.to_s

    "#{found} (matches summary)"
  end
  check('Users#profile') { "keys: #{users.profile(online_id: online_id).keys.first(5).join(', ')}" }
end

if account_id
  check('Users#profile_by_account_id') do
    "keys: #{users.profile_by_account_id(account_id: account_id).keys.join(', ')}"
  end
end

check('Users#played_games') do
  body = users.played_games
  "#{body['titles']&.size.to_i} titles in first page (#{body['totalItemCount'].inspect} in total)"
end
check('Account#devices') { "keys: #{account.devices.keys.join(', ')}" }
check('Account#library') do
  "#{account.library.dig('data', 'gameLibraryTitlesRetrieve', 'games')&.size.to_i} games (limit 100, no paging)"
end
check('Account#purchased_games') do
  "#{account.purchased_games.dig('data', 'purchasedTitlesRetrieve', 'games')&.size.to_i} games in first page (size 200)"
end

if @failures.empty?
  puts 'All checks passed.'
else
  warn "#{@failures.size} check(s) failed: #{@failures.join(', ')}"
  exit 1
end
