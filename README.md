# PSN::Client

A Ruby client for the PlayStation Network (PSN) API. Handles authentication via an NPSSO cookie and provides access to user trophy data.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add psn-client
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install psn-client
```

## Usage

### Environment variables

Authentication only needs your NPSSO token. To get it, sign in at playstation.com, then open <https://ca.account.sony.com/api/v1/ssocookie> and copy the `npsso` value. It lasts about two months.

| Variable | Required | Description |
|---|---|---|
| `PSN_NPSSO` | Yes | Your NPSSO token |
| `PSN_CLIENT_ID` | No | The PSN OAuth2 client ID. Defaults to the PlayStation app's public client (`PSN::Client::Auth::DEFAULT_CLIENT_ID`) |
| `PSN_BASIC_TOKEN` | No | The base64-encoded `client_id:client_secret`. Defaults to the PlayStation app's (`PSN::Client::Auth::DEFAULT_BASIC_TOKEN`). It is read once, when the gem loads |

The defaults are the same values listed in the [PSN API documentation](https://andshrew.github.io/PlayStation-Trophies/APIv2.html) and the bundled [API reference](docs/andshrew/APIv2.md). If you override `PSN_CLIENT_ID`, override `PSN_BASIC_TOKEN` to match.

### Authentication

```ruby
require 'psn/client'

access_token = PSN::Client::Auth.authenticate
```

`authenticate` exchanges your NPSSO token for a short-lived PSN access token string.

### Trophy data

Pass the access token to `PSN::Client::Trophies` and call the relevant method. All `user_id` parameters default to `'me'` (the authenticated user).

```ruby
trophies = PSN::Client::Trophies.new(access_token)

# Overall trophy level, points, and earned counts
trophies.trophy_summary
trophies.trophy_summary(user_id: 'example_user')

# List of trophy titles (games) for a user
trophies.trophy_titles
trophies.trophy_titles(limit: 100, offset: 0)

# Trophy groups defined for a title
# Use `platform:` shorthand ('PS3', 'PS4', 'PSVita', 'PS5', 'PC') or pass
# `np_service_name:` directly ('trophy' or 'trophy2').
trophies.title_trophy_groups(np_communication_id: 'NPWR12345_00', platform: 'PS5')

# Trophy group progress earned by a user on a title
trophies.earned_trophy_groups(np_communication_id: 'NPWR12345_00', platform: 'PS5')

# Full trophy list for a title
trophies.title_trophies(np_communication_id: 'NPWR12345_00', platform: 'PS5')

# Trophy earned status for a user on a title
trophies.earned_trophies(np_communication_id: 'NPWR12345_00', platform: 'PS5')
```

### User data

`PSN::Client::Users` looks up other players and their games. These use undocumented Sony endpoints that can change without notice.

```ruby
users = PSN::Client::Users.new(access_token)

# Search for players (raw GraphQL response, first page only; near-matches included)
results = users.search('example')
results.dig('data', 'universalContextSearch', 'results')

# Resolve an online ID to an account ID string, via the profile
# (raises PSN::Client::Error if not found, ArgumentError for an invalid online ID)
users.account_id('example_user')

# Profile for an online ID (returns the "profile" hash)
users.profile(online_id: 'example_user')

# Profile for a numeric account ID
users.profile_by_account_id(account_id: '1234567890123456789')

# Games played by a user (user_id defaults to 'me'; limit defaults to 200, the maximum)
users.played_games
users.played_games(user_id: '1234567890123456789', limit: 50, offset: 0)
```

`profile` and `account_id` raise `ArgumentError` for an invalid online ID, `profile_by_account_id` for a non-numeric account ID, and `played_games` for a `user_id` that is not `'me'` or numeric, or a `limit` above 200.

If a user's privacy settings block the request, Sony responds with HTTP 403 and the client raises `PSN::Client::PrivacyError` (see [Errors](#errors)).

```ruby
begin
  users.played_games(user_id: account_id)
rescue PSN::Client::PrivacyError
  # the user has hidden this data
end
```

### Signed-in account

`PSN::Client::Account` returns data about the authenticated account only. Like `Users`, it relies on undocumented Sony endpoints that can change.

```ruby
account = PSN::Client::Account.new(access_token)

# Registered devices
account.devices

# Game library (limit defaults to 100, the maximum)
account.library
account.library(limit: 20)

# Purchased games (size defaults to 200, start to 0)
account.purchased_games
account.purchased_games(size: 50, start: 0)

# Profile summary, including online ID and account ID
account.summary.dig('data', 'oracleUserProfileRetrieve')
```

`library` raises `ArgumentError` for a `limit` above 100. `library`, `purchased_games` and `summary` return the raw GraphQL response body.

### Errors

Every error the gem raises from a PSN call is a `PSN::Client::Error` (argument validation still raises `ArgumentError`). Rescue a subclass to handle a specific failure:

| Class | Raised when |
| --- | --- |
| `PSN::Client::AuthenticationError` | `Auth.authenticate` fails (expired or invalid NPSSO, rejected token exchange), or an API call returns HTTP 401. `error_code` holds Sony's OAuth error code, such as `"login_required"` for an expired NPSSO. |
| `PSN::Client::PrivacyError` | HTTP 403 caused by the target user's privacy settings |
| `PSN::Client::RateLimitError` | HTTP 429. `retry_at` is a `Time` from `X-RateLimit-Next-Available` or `Retry-After` (seconds counted from when the error was raised), or `nil` |
| `PSN::Client::GraphQLError` | A GraphQL response carries `errors`, even on HTTP 200. `errors` is the raw array and `data` any partial result |
| `PSN::Client::TransportError` | No response was received: DNS, connection, TLS or timeout failure |
| `PSN::Client::ParseError` | A successful response body, or the token exchange response, is not valid JSON (an empty body returns `nil` instead) |
| `PSN::Client::Error` | Any other non-2xx response |

Errors built from a response expose `status` (Integer), `headers` (Hash with lowercase names) and `body` (raw String); otherwise these are `nil`/empty. The original exception, for transport, parse and token-exchange failures, is available from `cause`.

```ruby
begin
  trophies.trophy_titles
rescue PSN::Client::RateLimitError => e
  sleep([e.retry_at - Time.now, 0].max) if e.retry_at
  retry
rescue PSN::Client::AuthenticationError
  access_token = PSN::Client::Auth.authenticate
  retry
rescue PSN::Client::Error => e
  warn "PSN request failed (#{e.status.inspect}): #{e.message}"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

For breakpoints while working on the gem, use Ruby's `debug` gem. After running `bin/setup` or `bundle install`, add `binding.break` where you want execution to pause and run the code under `bundle exec`, for example `bundle exec rspec` or `bundle exec ruby bin/verify_trophies.rb`.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MattyJacques/psn-client. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/MattyJacques/psn-client/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the PSN::Client project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/MattyJacques/psn-client/blob/main/CODE_OF_CONDUCT.md).
