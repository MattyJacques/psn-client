#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'debug'
require 'securerandom'
require 'psn/client'

# Live check of authentication and refresh against the real PSN API. It prints expiry
# times only: token values never reach the output, and debug logging (which includes the
# authorisation code) is turned off.
PSN.logger.level = Logger::INFO

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

def expiries(tokens)
  "access token expires #{tokens.expires_at}, refresh token expires #{tokens.refresh_token_expires_at}"
end

tokens = nil
refreshed = nil

check('Auth.tokens') do
  found = PSN::Client::Auth.tokens
  raise PSN::Client::Error, 'the response had no access token' if found.access_token.to_s.empty?
  raise PSN::Client::Error, 'the response had no refresh token' if found.refresh_token.to_s.empty?

  tokens = found
  expiries(tokens)
end

if tokens
  check('Auth.refresh') do
    refreshed = PSN::Client::Auth.refresh(tokens.refresh_token)
    "#{expiries(refreshed)}, refresh token unchanged: #{refreshed.refresh_token == tokens.refresh_token}"
  end
end

if refreshed
  check('Session from the refreshed tokens') do
    "trophy level #{PSN::Client::Session.new(refreshed).trophies.trophy_summary['trophyLevel']}"
  end
end

check('Auth.refresh with an unknown refresh token') do
  PSN::Client::Auth.refresh(SecureRandom.uuid)
  raise PSN::Client::Error, 'Sony accepted a made-up refresh token'
rescue PSN::Client::AuthenticationError => e
  raise unless e.error_code == 'invalid_grant'

  "rejected with #{e.error_code} (HTTP #{e.status})"
end

if @failures.empty?
  puts 'All checks passed.'
else
  warn "#{@failures.size} check(s) failed: #{@failures.join(', ')}"
  exit 1
end
