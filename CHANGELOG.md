## [Unreleased]

- `PSN_CLIENT_ID` and `PSN_BASIC_TOKEN` are now optional. They default to the PlayStation app's public OAuth client, so only `PSN_NPSSO` is required
- Added `PSN::Client::Users` with `search`, `account_id`, `profile`, `profile_by_account_id` and `played_games`
- Added `PSN::Client::Account` with `devices`, `library`, `purchased_games` and `summary`
- Added `PSN::Client::PrivacyError`, raised when a user's privacy settings block a request
- Added multi-host, POST and persisted-query GraphQL support to `Request`

## [0.1.0] - 2026-03-14

- Initial release
- Added `debug` as a development dependency for breakpoint-based gem debugging
- Added `trophy_summary` method to retrieve overall trophy level, points, and earned counts for a user
- Added `earned_trophies` method to retrieve trophy earned status for a user on a specific title
- Added `title_trophy_groups` and `earned_trophy_groups` methods for trophy group summary endpoints
