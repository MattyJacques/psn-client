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

Authentication requires three environment variables. You can find the values in the [PSN API documentation](https://andshrew.github.io/PlayStation-Trophies/APIv2.html) or the bundled [API reference](docs/andshrew/APIv2.md).

| Variable | Description |
|---|---|
| `PSN_NPSSO` | Your NPSSO token, obtained from a browser session on PlayStation.com |
| `PSN_BASIC_TOKEN` | The base64-encoded `client_id:client_secret` for the PSN OAuth2 client |
| `PSN_CLIENT_ID` | The PSN OAuth2 client ID |

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
