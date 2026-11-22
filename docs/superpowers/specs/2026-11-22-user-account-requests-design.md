# User and account requests: design

Date: 2026-11-22

## Intent

`psn-client` is published on RubyGems and must stay generic. Its long-term goal is to cover every PSN
request. Today it only covers trophies. This piece adds data about PSN accounts: who a user is,
what they've played, and details of the signed-in account. The first consumer will be the re-earn app.
In a future milestone it will switch to this gem from `psn-client-ruby`, the codebase in
`../ai-client`. The account creation date is out of scope here. The user is handling it separately.

## Goals

- Look up any user: resolve an online ID to an account ID, fetch their profile by online ID or
  account ID, and list the games they've played.
- Read details of the signed-in account: its devices, its game library, its purchased games, its
  subscription summary.
- Make it possible to tell a private profile apart from other failures.

## Non-goals

- Typed models, lazy pagination, token refresh, or a switch to Faraday. Those belong to a later
  rework, if one happens.
- Social calls (friends, presence, blocks), GraphQL (paged) search, store, and media. These come later, towards
  "cover all requests".
- Changes to re-earn.
- The account creation date. The user is handling it separately.

## Anti-goals

- **An estimated creation date.** Don't present a date inferred from trophies, games or devices as
  the creation date. The user said an estimate isn't worth having.
- **Breaking changes to the existing public API.** `Auth`, `Trophies`, and `Request#get(path)` with
  its current behaviour must keep working unchanged.

## Constraints

- Follow `.agent/workflows/development_standards.md`:
  - zero RuboCop offences
  - `# frozen_string_literal: true` at the top of every file
  - RSpec tests written with `expect(...)`
  - RBS signatures in `sig/`
  - README and CHANGELOG updated
- Single-quoted strings, matching the repo's RuboCop config. Ruby >= 3.1.
- Add no new runtime dependencies. Keep using `Net::HTTP` and `oauth2`.
- The endpoints are undocumented Sony internals and can change. Keep each endpoint's paths, hashes
  and quirks as constants in the class that uses it, with a comment saying how each was verified.
- Authentication stays as it is (`PSN::Client::Auth.authenticate` returns a token string). New classes
  take that token in their constructor, like `Trophies`.

## Approaches considered

- **A. Extend the gem in its current style (chosen).** Extend `Request` so it can reach other hosts
  and send POST and GraphQL requests. Add `Users` and `Account` classes that return raw parsed
  hashes, as `Trophies` does, and add a `PrivacyError`. It breaks nothing, keeps the gem thin, and
  reuses endpoints already proven in ai-client and the old backlog manager. The cost is that callers
  parse the responses themselves.
- **B. Rebuild on ai-client's foundations first.** That means Faraday, typed models, paging and a
  full error hierarchy. It's a better base for full coverage, but it's a breaking rewrite before any
  user data ships. It's also close to merging the two gems, which the user turned down.
- **C. Creation date only, estimated from trophy or game dates.** Rejected because an estimate isn't
  wanted. The real creation date is now out of scope and handled separately.

## Design

### `Request` (extended, backward compatible)

- Add a `HOSTS` map:
  - `mobile`: `https://m.np.playstation.com/api`, the current `BASE_URL`, so existing `Trophies`
    paths are unchanged
  - `community`: `https://us-prof.np.community.playstation.net`
  - `dms`: `https://dms.api.playstation.com`
  - `web`: `https://web.np.playstation.com/api`
- Keep `BASE_URL` as a constant equal to the mobile entry.
- Methods:
  - `get(path, host: :mobile, headers: {})`, which keeps the current behaviour when called as
    `get(path)`
  - `post(path, body, host: :mobile, headers: {})`, which sends a JSON body
  - `graphql(operation_name, variables, sha256_hash, host: :mobile, headers: {})`, a
    persisted-query GET to `/graphql/v1/op` with `operationName`, `variables` (JSON) and
    `extensions` (`{"persistedQuery":{"version":1,"sha256Hash":...}}`) as query parameters, and the
    `Apollo-Require-Preflight: true` header. The JSON-valued parameters must be URL-encoded (for
    example with `URI.encode_www_form`), unlike `Trophies`' raw `build_query_string`. Sony can return HTTP 200 with an `errors` array; raise
    `Error` in that case.
- Map errors:
  - 403 with a JSON `error.message` matching `/access control|privacy/i` raises
    `PSN::Client::PrivacyError` (a subclass of `PSN::Client::Error`)
  - every other non-2xx response raises `Error`, as now
  - error messages keep the current `Request failed: <code> <message> - <body>` text

### `PSN::Client::Users` (any account)

Constructed with an access token. Methods:

- `search(term)`: POST to `/search/v1/universalSearch` with
  `{"searchTerm": term, "domainRequests": [{"domain": "SocialAllAccounts"}]}`. Returns Sony's raw
  response, near-matches included, so callers can choose for themselves. It returns a single page;
  paged search uses the GraphQL queries, which come later. (Added at the user's request.)
- `account_id(online_id)`: calls `search(online_id)`, the same POST with
  `{"searchTerm": online_id, "domainRequests": [{"domain": "SocialAllAccounts"}]}`. It finds the
  result whose `socialMetadata.onlineId` matches case-insensitively and returns its `accountId`.
  It raises `Error` if there's no match. This is the only method that returns a value rather than
  the raw body, because its whole job is the lookup.
- `profile(online_id:)`: legacy `profile2` on the community host, with the field list from ai-client's
  `Profiles::PROFILE2_FIELDS`. Returns the `profile` hash. `profile2` rejects `"me"`, so `online_id`
  is required and is validated against `/\A[a-zA-Z0-9_-]{3,16}\z/`, raising `ArgumentError`.
- `profile_by_account_id(account_id:)`: `/userProfile/v1/internal/users/{id}/profiles`. Rejects
  `"me"`.
- `played_games(user_id: 'me', limit: 200, offset: 0)`: `/gamelist/v2/users/{id}/titles`. The limit
  is capped at 200: ai-client verified that 201 returns HTTP 400. Each entry carries
  `firstPlayedDateTime`, `lastPlayedDateTime` and `playDuration`.

The `user_id: 'me'` keyword default matches `Trophies`.

### `PSN::Client::Account` (signed-in account only)

Constructed with an access token. Methods:

- `devices`: dms `/api/v1/devices/accounts/me` with
  `includeFields=device,systemData&platform=PS5,PS4,PS3,PSVita`. Devices carry `activationDate`.
- `library(limit: 100)`: GraphQL `getUserGameList`
  (hash `e0136f81d7d1fb6be58238c574e9a46e1c0cc2f7f6977a08a5a46f224523a004`) with
  `categories: 'ps4_game,ps5_native_game'`. The limit is capped at 100.
- `purchased_games(size: 200, start: 0)`: GraphQL `getPurchasedGameList`
  (hash `827a423f6a8ddca4107ac01395af2ec0eafd8396fc7fa204aaf9b7ed2eefa168`) with
  `isActive: true, platform: ['ps4','ps5'], sortBy: 'ACTIVE_DATE', sortDirection: 'desc'`.
- `summary`: GraphQL `getProfileOracle`
  (hash `fc0d765f537f3dce3e0d91c71e85daa401042ba43066acde9f8f584faced10df`) on the `web` host,
  with the `apollographql-client-name: oracle` header. It returns the online ID, account ID, age,
  PS Plus status, and the subscription list.

Builder's call, flagged: GraphQL methods return the full parsed body, as REST methods do. That keeps
one rule ("you get Sony's JSON") instead of unwrapping `data.*`.

### Limits

`played_games(limit:)` above 200 and `library(limit:)` above 100 raise `ArgumentError`; they are not
silently clamped. Raising now and relaxing to clamping later is not a breaking change; the reverse
would be. (Builder's call.)

### Live check script

Add `bin/verify_users.rb`, modelled on `bin/verify_trophies.rb`. It calls each new method against
the real API and prints a short summary. It's not part of the test suite. Use it to confirm the
endpoints still work.

### Tests, types, docs

- Specs:
  - `spec/psn/client/users_spec.rb` and `account_spec.rb`, which stub `Request` the way
    `trophies_spec.rb` does
  - extend `request_spec.rb` to cover hosts, POST, GraphQL encoding, GraphQL errors and
    `PrivacyError`
  - keep the existing specs passing unchanged
- RBS for `Request`, `Users`, `Account` and `PrivacyError`.
- README usage section for both classes, and a CHANGELOG entry under `[Unreleased]`. Bump the
  version to 0.2.0 at release time, not in this work.

## Left to the builder

- How `Request` builds URLs per host and passes query parameters (string paths, as `Trophies` does
  now, or a params hash). Either is fine, as long as the existing `get(path)` callers are unaffected.
- Spec structure and fixture shapes.
- Wording of the README and CHANGELOG.
