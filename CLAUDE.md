# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`psn-client` is a Ruby gem (Ruby >= 3.1) wrapping the PlayStation Network API: NPSSO-cookie authentication plus trophy, user and account endpoints. The only runtime dependency is `oauth2`; HTTP is done with `Net::HTTP` directly.

## Commands

```bash
bin/setup                                   # bundle install (run first; nothing works under `bundle exec` until gems are installed)
bundle exec rake                            # default task: spec + rubocop — exactly what CI runs (Ruby 3.1–3.4 matrix)
bundle exec rspec                           # all specs; writes a SimpleCov report to coverage/
bundle exec rspec spec/psn/client/trophies_spec.rb       # one file
bundle exec rspec spec/psn/client/trophies_spec.rb:55    # one example/group by line
bundle exec rspec --only-failures           # re-run failures (tracked in .rspec_status)
bundle exec rubocop                         # lint; `-a` (or `rake rubocop:autocorrect`) for safe autocorrect
bin/console                                 # IRB with the gem loaded
bundle exec ruby bin/verify_trophies.rb     # live smoke test against the real PSN API (needs the env vars below)
bundle exec ruby bin/verify_users.rb        # live smoke test of Users and Account; exits 1 if any check fails
```

- `Gemfile.lock` is gitignored, so dependency versions resolve fresh per machine and per CI run. A lint failure that appears without a code change is usually a newer RuboCop (`NewCops: enable` is on).
- The suite is at 100% line coverage. No minimum is enforced, and single-file runs report a low percentage — ignore it.
- Breakpoints: add `binding.break` and run under `bundle exec`. The `debug` gem is already required by `spec_helper`, `bin/console`, and `bin/verify_trophies.rb`.
- Release: bump `lib/psn/client/version.rb`, move the `[Unreleased]` entries in `CHANGELOG.md` under the new version, then `bundle exec rake release` (tags, pushes, and publishes to RubyGems — only on explicit request). Packaged files come from `git ls-files`, so untracked files are not shipped.

## Architecture

Everything lives under `PSN::Client` in `lib/psn/client/`; `require 'psn/client'` loads it all. The gem is two independent steps that the caller wires together with a plain token string — there is no client object holding state, and no token caching or refresh.

1. **`Auth`** (`auth.rb`) — `Auth.authenticate` returns the access token as a *string*. It sends a GET to Sony's OAuth authorize URL carrying the `npsso` cookie, reads the auth code out of the redirect `Location` header (the redirect targets a mobile app scheme and is never followed), then exchanges the code for a JWT via the `oauth2` gem. Errors are derived from, in order: an `error_description` in the redirect query or JSON body, the `login_required` error code (expired NPSSO), or a generic fallback. They are logged and raised as `AuthenticationError` (with `error_code` and the response's status/headers/body); `OAuth2::Error` from the token exchange becomes `AuthenticationError` too, a malformed JSON token response becomes `ParseError`, and network failures (including any `Faraday::Error`) become `TransportError`. The exception is by status (`Error.from_auth_response`): a 429 from either step raises `RateLimitError` and a 5xx plain `Error`, so outages are not mistaken for bad credentials. A redirect `Location` that cannot be parsed raises `AuthenticationError`.
2. **API classes** — each is instantiated with the token, builds one `Request`, and returns the parsed JSON untouched (no model objects, no automatic pagination):
   - **`Trophies`** (`trophies.rb`) — builds paths and query strings by hand and calls `Request#get` on the mobile host.
   - **`Users`** (`users.rb`) — `search` (persisted GraphQL), `account_id`/`profile` by online ID (profile2 on the `community` host), `profile_by_account_id`, and `played_games`. Online IDs, account IDs and user IDs are validated against regexes before they reach a path.
   - **`Account`** (`account.rb`) — the signed-in account only: `devices` (`dms` host), and `library`, `purchased_games` and `summary` (persisted GraphQL; `summary` uses the `web` host).
   - **`Pagination`** (`pagination.rb`) — mixed into `Users` and `Account`; `validate_page_param!` raises `ArgumentError` unless a limit/offset/size/start is an Integer within bounds. Upper bounds are only set where Sony's limit was verified live.
3. **`Request`** (`request.rb`) — the single HTTP layer for API calls. `get`, `post` and `graphql` take a `host:` key into `HOSTS` (`:mobile` default, `:community`, `:dms`, `:web`), add the Bearer header and a `psn-client/<version>` User-Agent (Sony's search fails on Ruby's default), URL-encode `params:`, and merge caller `headers:`. `graphql` sends a persisted-query GET to `/graphql/v1/op` with `Apollo-Require-Preflight` and raises `GraphQLError` (keeping `errors` and partial `data`) if the body has `errors`, even on HTTP 200. A non-2xx raises `AuthenticationError` (401), `RateLimitError` (429), `PrivacyError` (403 whose JSON error message mentions access control or privacy) or plain `Error`; network exceptions become `TransportError` and invalid JSON `ParseError`; an empty 2xx body returns `nil` from `get`/`post` (callers must cope, as `Users#profile` does) and raises `ParseError` from `graphql`.

**Errors** (`errors.rb`) — everything raised from a PSN call derives from `PSN::Client::Error`, which carries `status`, `headers` (lowercased names) and `body` when built from a response (`Error.details_from(response)`). Raise inside the `rescue` so Ruby sets `cause`. `TransportError::NETWORK_ERRORS` is the shared list of `Net::HTTP` network exceptions.

Things that are easy to get wrong:

- **Configuration is env-only**: `PSN_NPSSO` (required), `PSN_CLIENT_ID` and `PSN_BASIC_TOKEN` (optional, defaulting to `Auth::DEFAULT_CLIENT_ID` / `DEFAULT_BASIC_TOKEN`, the PlayStation app's public OAuth client). `Auth::BASIC_TOKEN` is a constant read from ENV when the file is *loaded*; the other two are read lazily per call. Setting or stubbing `PSN_BASIC_TOKEN` after load has no effect (the `ENV.fetch` stub for it in `auth_spec.rb` is inert — use `stub_const` to control it).
- **`np_service_name:` vs `platform:`** — title-scoped methods accept one or the other; passing both raises `ArgumentError`. `platform:` maps PS3/PS4/PSVita → `trophy` and PS5/PC → `trophy2` (`resolve_service_name`). Passing neither, or an unrecognised platform, silently omits `npServiceName`, which the API rejects for PS3/PS4/PSVita titles.
- **Trophies query strings are not URL-encoded** (unlike `Request`'s `params:`) — `build_query_string` drops `nil` values and interpolates the rest raw. Optional `limit:`/`offset:` on `title_trophies`/`earned_trophies` travel through `**options`, so any other keyword passed there is silently ignored.
- **`PSN.logger`** (`lib/psn/logger.rb`) defaults to `Rails.logger` when Rails is defined, otherwise stdout, and is memoized; override with `PSN.logger=`. Debug-level logging includes the raw auth code.

`docs/andshrew/APIv2.md` is a vendored copy of the community PSN trophy API reference. Consult it for endpoint paths, parameters, and response shapes before adding or changing `Trophies` methods; it also documents endpoints not yet wrapped (per-title trophy summary by title ID, Game Help, language header, rate limits).

## Testing conventions

No HTTP-mocking library is used and specs never touch the network. Collaborators are stubbed with `instance_double`:

- `Trophies` specs stub `Request.new`/`#get` and assert on the **exact path string**, so parameter order in `build_query_string` calls is part of the tested contract. `Users` and `Account` specs stub `Request.new` the same way and assert on `#get`/`#graphql` arguments.
- Stubs (`allow`) go in `before` blocks, never inside `it`; check calls afterwards with `have_received`. No cop enforces this.
- `Auth` specs stub `Net::HTTP.new`, `OAuth2::Client`, `ENV.fetch`, and `PSN.logger`; `Request` specs stub `Net::HTTP.start`. Both return real `Net::HTTPResponse` objects built with `http_response(code, body, headers)` (`spec/support/http_responses.rb`, included in every example), because errors read `code`, `each_header` and `body`.

Monkey-patching is disabled (`RSpec.describe` and `expect` syntax only). RuboCop RSpec limits are set in `.rubocop.yml`: 15 lines per example, 3 expectations per example, 10 memoized helpers, 4 nesting levels. `Metrics/ClassLength` is raised to 150 lines, and `Metrics/ParameterLists` is disabled only for `trophies.rb`.

## Project rules (from `.github/copilot-instructions.md`)

- Introduce no new RuboCop offenses.
- Every Ruby file starts with `# frozen_string_literal: true`.
- New functionality and bug fixes need RSpec coverage.
- Update the RBS signatures in `sig/` whenever a method signature changes or a public method is added. `sig/` mirrors `lib/` one-to-one and includes private methods; nothing type-checks it in CI, so it must be kept in sync by hand.
- When public API changes, update the `README.md` usage section and add an entry under `[Unreleased]` in `CHANGELOG.md`.
