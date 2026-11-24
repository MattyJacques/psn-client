## [Unreleased]

## [0.3.0] - 2026-11-24

- **Breaking:** `Trophies` validates the IDs it puts in request paths and raises `ArgumentError` before any request is made: `user_id` must be `'me'` or a numeric account ID, `np_communication_id` must look like `NPWR12345_00`, and `trophy_group_id` must be `'all'`, `'default'` or three digits such as `'001'`. Sony already answered HTTP 400 for anything else, including online IDs passed as `user_id`
- **Breaking:** `limit` and `offset` on `Trophies#trophy_titles`, `#title_trophies` and `#earned_trophies` must be Integers (`limit` at least 1, `offset` at least 0), or `ArgumentError` is raised. `trophy_titles` also rejects a `limit` above 800, Sony's maximum. Numeric strings such as `limit: '10'` are no longer accepted
- **Breaking:** `Trophies#title_trophies` and `#earned_trophies` raise `ArgumentError` for an unknown keyword instead of silently ignoring it
- `Trophies` query parameters are now URL-encoded by `Request`, and requests with no query parameters no longer end in a bare `?`
- `Auth.authenticate` and `Auth.new` accept `npsso:`, `client_id:` and `basic_token:`. The `PSN_*` environment variables remain the defaults
- `PSN_BASIC_TOKEN` is now read when authenticating instead of once when the gem loads, so setting it after `require` takes effect
- **Breaking:** removed the `Auth::BASIC_TOKEN` constant. Use `Auth::DEFAULT_BASIC_TOKEN`, or pass `basic_token:`
- `Trophies`, `Users` and `Account` accept `request:` to inject a request object in place of an access token
- `Request.new` accepts `open_timeout:`, `read_timeout:` and `write_timeout:`
- `Auth.authenticate`, `Auth.new`, `Session.authenticate` and `Session.new` accept the same three timeouts. `Auth` applies them to the authorisation request and the token exchange, and `Session` to the request it builds; passing them to `Session.new` with `request:` raises `ArgumentError`
- Added `PSN::Client::Session`, which shares one request across `trophies`, `users` and `account`, with `Session.authenticate` to build one from credentials
- **Breaking:** `Auth.authenticate` raises `PSN::Client::AuthenticationError` (or `TransportError`) instead of `RuntimeError`. Code rescuing `RuntimeError` must rescue `PSN::Client::Error` or a subclass
- **Breaking:** an API response of HTTP 401 raises `PSN::Client::AuthenticationError`, and GraphQL errors raise `PSN::Client::GraphQLError`. Both are still `PSN::Client::Error` subclasses
- Added structured errors: `PSN::Client::Error` now exposes `status`, `headers` and `body`, and new subclasses `AuthenticationError` (`error_code`), `RateLimitError` (`retry_at`), `GraphQLError` (`errors`, `data`), `TransportError` and `ParseError` cover authentication, HTTP 429, GraphQL, network and invalid-JSON failures
- Network failures and invalid JSON bodies no longer escape as `Net::*`, `SocketError`, `Errno::*`, `Faraday::*` or `JSON::ParserError`; the original exception is kept as `cause`
- A successful response with an empty body (such as HTTP 204) returns `nil` instead of raising `TypeError`. `Users#profile` returns `nil` for one, and an empty GraphQL response raises `ParseError`
- `Auth.authenticate` raises `RateLimitError` for HTTP 429 and plain `PSN::Client::Error` for HTTP 5xx, from either the authorisation request or the token exchange, instead of reporting them as `AuthenticationError`
- A malformed authorisation redirect raises `AuthenticationError`, and any `Faraday::Error`, corrupt compressed body or malformed response header raises `TransportError`
- `RateLimitError#retry_at` falls back to `Retry-After` when `X-RateLimit-Next-Available` is not a whole number
- `Auth.authenticate` no longer fails under debug logging when the token response has no `expires_in`
- Added `PSN::Client::Tokens`, which holds `access_token`, `expires_at`, `refresh_token` and `refresh_token_expires_at`, with `expired?` and `refresh_token_expired?`. Its `inspect` leaves the token values out
- Added `Auth.tokens` and `Auth#tokens`, which authenticate like `Auth.authenticate` but return `Tokens`, so the refresh token Sony issues is no longer discarded. `Auth.authenticate` still returns the access token string
- Added `Auth.refresh(refresh_token)` and `Auth#refresh`, which trade a refresh token for new `Tokens` without the NPSSO. A refresh token Sony no longer accepts raises `AuthenticationError` with an `error_code` of `"invalid_grant"`, and a `nil` or blank one raises `ArgumentError`
- Added `Session#tokens` and `Session.from_refresh_token(refresh_token)`, and `Session.new` accepts `Tokens` in place of an access token string. Nothing is refreshed automatically
- The `ParseError` for a malformed token response no longer repeats the JSON parser's message, which could quote the response body and any tokens in it. The parser's error is still available from `cause`

## [0.2.0] - 2026-11-23

- `PSN_CLIENT_ID` and `PSN_BASIC_TOKEN` are now optional. They default to the PlayStation app's public OAuth client, so only `PSN_NPSSO` is required
- Added `PSN::Client::Users` with `search`, `account_id`, `profile`, `profile_by_account_id` and `played_games`
- Added `PSN::Client::Account` with `devices`, `library`, `purchased_games` and `summary`
- Pagination arguments on `Users` and `Account` (`limit`, `offset`, `size`, `start`) must be Integers within bounds, or `ArgumentError` is raised
- Added `PSN::Client::PrivacyError`, raised when a user's privacy settings block a request
- Added multi-host, POST and persisted-query GraphQL support to `Request`
- `Request` now sends `User-Agent: psn-client/<version>` on every request (Sony's search backend rejects Net::HTTP's default `Ruby`)

## [0.1.0] - 2026-03-14

- Initial release
- Added `debug` as a development dependency for breakpoint-based gem debugging
- Added `trophy_summary` method to retrieve overall trophy level, points, and earned counts for a user
- Added `earned_trophies` method to retrieve trophy earned status for a user on a specific title
- Added `title_trophy_groups` and `earned_trophy_groups` methods for trophy group summary endpoints
