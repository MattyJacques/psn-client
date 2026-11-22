# User and Account Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `PSN::Client::Users` (any account) and `PSN::Client::Account` (signed-in account) request
classes, on top of a `Request` that can reach several PSN hosts and send POST and GraphQL requests.

**Architecture:** `Request` gains a `HOSTS` map, `params:`/`headers:`/`host:` keywords on `get`, plus
`post` and `graphql`. It also raises `PrivacyError` on access-control 403s. `Users` and `Account` mirror
`Trophies`: each is built with a token, delegates to `Request`, and returns Sony's parsed JSON.

**Tech Stack:** Ruby >= 3.1, `Net::HTTP`, `json`, `uri`, RSpec with `instance_double` (no HTTP-mocking
library), RBS in `sig/`, RuboCop.

**Spec:** `docs/superpowers/specs/2026-11-22-user-account-requests-design.md`

## Global Constraints

- **Branch:** work on `user-account-requests`. Never commit to `main`.
- **File header:** every Ruby file starts with `# frozen_string_literal: true`.
- **Dependencies:** no new runtime dependencies (only `oauth2`). Use `Net::HTTP`, `json` and `uri` from
  the standard library.
- **Style:** single-quoted strings. Zero new RuboCop offences. `bundle exec rake` (spec + rubocop) must
  pass after every task.
- **RSpec:** `RSpec.describe` and `expect` only. Each example has at most 15 lines and at most 3
  expectations, with at most 10 memoized helpers.
- **Signatures:** `sig/` mirrors `lib/` one-to-one, private methods included. Update it in the same task
  as the code.
- **Backward compatibility:** `Auth`, `Trophies`, and `Request#get(path)` behave exactly as today. The
  existing specs pass unchanged.
- **Undocumented endpoints:** each endpoint's paths, hashes and quirks live as constants in the class
  that uses them, with a comment saying how each was verified ("verified live, <date>").
- **Returns:** every method returns Sony's full parsed body. There are two exceptions:
  - `Users#account_id` returns a `String`
  - `Users#profile` returns the `profile` hash

## Review Focus

1. **A search returns only a near-match.** For example, `account_id('foo')` gets back only `foo_bar`.
   It must raise `Error` rather than return the wrong account. Pinned in Task 3.
2. **A 403 with an HTML or other non-JSON body** (an edge or WAF block) raises a plain `Error`. It must
   not raise `PrivacyError` or leak a `JSON::ParserError`. Pinned in Task 1.
3. **Legacy `get(path)` with a query already in the path** (as `Trophies` does) sends the path
   untouched. No stray `?` or `&` is added when `params` is empty. Pinned in Task 1.
4. **The search response is missing `domainResponses`** or has an empty result list. This raises `Error`
   ("no PSN account found"), not `NoMethodError`. Pinned in Task 3.
5. **A GraphQL 200 with `"errors": []`** (an empty array) is treated as success, not an error. Pinned in
   Task 2.

---

### Task 1: Multi-host `Request#get` and `PrivacyError`

**Files:**
- Modify: `lib/psn/client.rb` (add `PrivacyError`)
- Modify: `lib/psn/client/request.rb`
- Modify: `sig/psn/client.rbs`, `sig/psn/client/request.rbs`
- Test: `spec/psn/client/request_spec.rb`, `spec/psn/client_spec.rb`

**Interfaces:**
- Produces:
  - `PSN::Client::PrivacyError < PSN::Client::Error`
  - `Request::HOSTS`, a frozen `Hash[Symbol, String]`:
    - `mobile: 'https://m.np.playstation.com/api'`
    - `community: 'https://us-prof.np.community.playstation.net'`
    - `dms: 'https://dms.api.playstation.com'`
    - `web: 'https://web.np.playstation.com/api'`
  - `Request::BASE_URL == HOSTS[:mobile]`
  - `Request#get(path, host: :mobile, params: {}, headers: {}) -> untyped`. `params` are
    URL-encoded with `URI.encode_www_form` and appended with `?`, or with `&` if the path already has a
    `?`. They're omitted when empty. An unknown host raises `KeyError` (via `HOSTS.fetch`).

- [ ] **Step 1: Write the failing tests.** Add these to `request_spec.rb`, under `describe '#get'`, reusing
  the existing `Net::HTTP.start` / `captured_requests` stubs:

```ruby
it 'leaves a legacy path with its own query untouched' do
  request_service.get('/trophy?limit=1')
  expect(captured_requests.last.path).to eq('/api/trophy?limit=1')
end

it 'URL-encodes params' do
  request_service.get('/x', params: { 'fields' => 'a,b(c)', 'n' => 1 })
  expect(captured_requests.last.path).to eq('/api/x?fields=a%2Cb%28c%29&n=1')
end

it 'targets another host' do
  request_service.get('/userProfile/v1/users/abc/profile2', host: :community)
  expect(Net::HTTP).to have_received(:start).with('us-prof.np.community.playstation.net', 443, use_ssl: true)
  expect(captured_requests.last.path).to eq('/userProfile/v1/users/abc/profile2')
end

it 'sends extra headers' do
  request_service.get('/x', headers: { 'apollographql-client-name' => 'oracle' })
  expect(captured_requests.last['apollographql-client-name']).to eq('oracle')
end

context 'when forbidden by access control' do
  let(:response) do
    instance_double(Net::HTTPForbidden, code: '403', message: 'Forbidden',
                                        body: '{"error":{"message":"Not permitted by access control"}}')
  end

  it 'raises PrivacyError' do
    expect { request_service.get('/test') }.to raise_error(PSN::Client::PrivacyError, /Request failed: 403/)
  end
end

context 'when forbidden with a non-JSON body' do
  let(:response) { instance_double(Net::HTTPForbidden, code: '403', message: 'Forbidden', body: '<html>') }

  it 'raises a plain Error' do
    expect { request_service.get('/test') }.to raise_error(PSN::Client::Error) { |e|
      expect(e).not_to be_a(PSN::Client::PrivacyError)
    }
  end
end
```

  Add `describe PSN::Client::PrivacyError` to `client_spec.rb`, asserting
  `expect(described_class.ancestors).to include(PSN::Client::Error)`.

- [ ] **Step 2: Run the tests to confirm they fail.**
  Run: `bundle exec rspec spec/psn/client/request_spec.rb spec/psn/client_spec.rb`
  Expected: the new examples FAIL with `ArgumentError` (unknown keyword) or
  `NameError: uninitialized constant PSN::Client::PrivacyError`.

- [ ] **Step 3: Implement.**
  - Add `class PrivacyError < Error; end` in `lib/psn/client.rb`, next to `Error`.
  - In `Request`:
    - Add `HOSTS` and set `BASE_URL = HOSTS[:mobile]`.
    - Change `get` to the signature above.
    - Pull out a private `perform(uri, http_request)` that does the
      `Net::HTTP.start(uri.hostname, uri.port, use_ssl: true)` call, so that Task 2 can reuse it.
    - Add a private `build_uri(host, path, params) -> URI`.
    - In `parse_response`, a 403 whose body parses as JSON, and whose `error.message` (or a string
      `error`) matches `/access control|privacy/i`, raises `PrivacyError`. Anything else keeps the
      current `Error` and its message. Rescue `JSON::ParserError` in that check.
  - Update both RBS files to match.

- [ ] **Step 4: Run the full suite.**
  Run: `bundle exec rake`
  Expected: all specs pass and RuboCop reports no offences.

- [ ] **Step 5: Commit.**
  `git commit -am "Support multiple hosts, params and headers in Request; add PrivacyError"`

### Task 2: `Request#post` and `Request#graphql`

**Files:**
- Modify: `lib/psn/client/request.rb`, `sig/psn/client/request.rbs`
- Test: `spec/psn/client/request_spec.rb`

**Interfaces:**
- Consumes (from Task 1): `HOSTS`, the private `perform`, `build_uri` and `parse_response`
- Produces:
  - `Request#post(path, body, host: :mobile, headers: {}) -> untyped`. It sends `JSON.generate(body)`
    with `Content-Type: application/json` and the Bearer header, and parses the response like `get`.
  - `Request::GRAPHQL_PATH = '/graphql/v1/op'`
  - `Request#graphql(operation_name, variables, sha256_hash, host: :mobile, headers: {}) -> untyped`.
    It's a GET to `GRAPHQL_PATH` with:
    - params `operationName`, `variables` (`JSON.generate(variables)`), and `extensions`
      (`JSON.generate({ 'persistedQuery' => { 'version' => 1, 'sha256Hash' => sha256_hash } })`)
    - the header `Apollo-Require-Preflight: true`, merged with `headers`

    If the parsed body is a `Hash` with a non-empty `errors` array, it raises
    `Error, "PSN GraphQL error: #{messages.join('; ')}"`.

- [ ] **Step 1: Write the failing tests.** Add `describe '#post'` and `describe '#graphql'` with the same
  `Net::HTTP.start` stubbing:

```ruby
# #post
it 'sends a JSON body' do
  request_service.post('/search/v1/universalSearch', { 'searchTerm' => 'abc' })
  req = captured_requests.last
  expect(req).to have_attributes(method: 'POST', path: '/api/search/v1/universalSearch', body: '{"searchTerm":"abc"}')
  expect(req['Content-Type']).to eq('application/json')
end

# #graphql
it 'encodes a persisted query' do
  request_service.graphql('getUserGameList', { 'limit' => 1 }, 'abc123')
  query = URI.decode_www_form(URI(captured_requests.last.path).query).to_h
  expect(query).to eq('operationName' => 'getUserGameList', 'variables' => '{"limit":1}',
                      'extensions' => '{"persistedQuery":{"version":1,"sha256Hash":"abc123"}}')
  expect(captured_requests.last['Apollo-Require-Preflight']).to eq('true')
end

it 'uses the web host' do
  request_service.graphql('op', {}, 'h', host: :web)
  expect(Net::HTTP).to have_received(:start).with('web.np.playstation.com', 443, use_ssl: true)
  expect(URI(captured_requests.last.path).path).to eq('/api/graphql/v1/op')
end

context 'when the body carries GraphQL errors' do # response body: '{"errors":[{"message":"bad"},{"message":"worse"}]}'
  it 'raises Error' do
    expect { request_service.graphql('op', {}, 'h') }.to raise_error(PSN::Client::Error, 'PSN GraphQL error: bad; worse')
  end
end

context 'when errors is empty' do # response body: '{"data":{},"errors":[]}'
  it 'returns the body' do
    expect(request_service.graphql('op', {}, 'h')).to eq('data' => {}, 'errors' => [])
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail.**
  Run: `bundle exec rspec spec/psn/client/request_spec.rb`
  Expected: FAIL with `NoMethodError: undefined method 'post'` / `'graphql'`.

- [ ] **Step 3: Implement `post` and `graphql` as specified, and update the RBS.**

- [ ] **Step 4: Run the full suite.**
  Run: `bundle exec rake`
  Expected: it passes with no offences.

- [ ] **Step 5: Commit.**
  `git commit -am "Add POST and persisted-query GraphQL support to Request"`

### Task 3: `PSN::Client::Users`

**Files:**
- Create: `lib/psn/client/users.rb`, `sig/psn/client/users.rbs`, `spec/psn/client/users_spec.rb`
- Modify: `lib/psn/client.rb` (add `require_relative 'client/users'`)

**Interfaces:**
- Consumes: `Request#get(path, host:, params:)`, `Request#post(path, body)`, `Error`
- Produces:
  - `Users.new(access_token)`
  - `#search(term) -> untyped`: the raw universalSearch body
  - `#account_id(online_id) -> String`: built on `search`
  - `#profile(online_id:) -> Hash`
  - `#profile_by_account_id(account_id:) -> untyped`
  - `#played_games(user_id: 'me', limit: 200, offset: 0) -> untyped`
- Constants:
  - `SEARCH_PATH = '/search/v1/universalSearch'`
  - `SEARCH_DOMAIN = 'SocialAllAccounts'`
  - `PROFILE2_PATH = '/userProfile/v1/users/%s/profile2'`, on the `:community` host
  - `PROFILE2_FIELDS = 'npId,onlineId,accountId,avatarUrls,plus,aboutMe,languagesUsed,trophySummary(@default,level,progress,earnedTrophies),isOfficiallyVerified,primaryOnlineStatus,presences(@default,@titleInfo,platform,lastOnlineDate)'`
  - `PROFILE_BY_ACCOUNT_PATH = '/userProfile/v1/internal/users/%s/profiles'`
  - `PLAYED_GAMES_PATH = '/gamelist/v2/users/%s/titles'`
  - `PLAYED_GAMES_MAX_LIMIT = 200` (201 returns HTTP 400, verified live)
  - `ONLINE_ID_PATTERN = /\A[a-zA-Z0-9_-]{3,16}\z/`

- [ ] **Step 1: Write the failing tests.** Stub `Request.new(access_token)` with
  `instance_double(PSN::Client::Request)`, the way `trophies_spec.rb` does. Assert the exact arguments:

```ruby
# #search
it 'returns the raw search response, near-matches included' do
  allow(request).to receive(:post).with('/search/v1/universalSearch', search_body).and_return(results(%w[Foo_Bar 1]))
  expect(users.search('Foo')).to eq(results(%w[Foo_Bar 1]))
end

# #account_id
let(:search_body) { { 'searchTerm' => 'Foo', 'domainRequests' => [{ 'domain' => 'SocialAllAccounts' }] } }
def results(*ids) = { 'domainResponses' => [{ 'results' => ids.map { |id, acc| { 'socialMetadata' => { 'onlineId' => id, 'accountId' => acc } } } }] }

it 'returns the account ID of the case-insensitive exact match' do
  allow(request).to receive(:post).with('/search/v1/universalSearch', search_body).and_return(results(%w[Foo_Bar 1], %w[foo 2]))
  expect(users.account_id('Foo')).to eq('2')
end
it 'raises Error when only a near-match comes back' do   # Review Focus 1
  allow(request).to receive(:post).and_return(results(%w[Foo_Bar 1]))
  expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
end
it 'raises Error when domainResponses is missing' do     # Review Focus 4
  allow(request).to receive(:post).and_return({})
  expect { users.account_id('Foo') }.to raise_error(PSN::Client::Error, /no PSN account found/)
end

# #profile
it 'returns the profile hash' do
  allow(request).to receive(:get).with('/userProfile/v1/users/Foo/profile2', host: :community,
                                       params: { 'fields' => described_class::PROFILE2_FIELDS })
                                 .and_return('profile' => { 'onlineId' => 'Foo' })
  expect(users.profile(online_id: 'Foo')).to eq('onlineId' => 'Foo')
end
it('rejects me')      { expect { users.profile(online_id: 'me') }.to raise_error(ArgumentError) }
it('rejects nil')     { expect { users.profile(online_id: nil) }.to raise_error(ArgumentError) }

# #profile_by_account_id
#   expects get('/userProfile/v1/internal/users/123/profiles') and returns the body
#   raises ArgumentError for account_id: 'me'

# #played_games
#   expects get('/gamelist/v2/users/me/titles', params: { 'limit' => 200, 'offset' => 0 })
#   passes user_id/limit/offset through
#   raises ArgumentError for limit: 201
```

- [ ] **Step 2: Run the tests to confirm they fail.**
  Run: `bundle exec rspec spec/psn/client/users_spec.rb`
  Expected: FAIL with `uninitialized constant PSN::Client::Users`.

- [ ] **Step 3: Implement `lib/psn/client/users.rb` with the interface and constants above.**
  - `profile` validates against `ONLINE_ID_PATTERN` and raises
    `ArgumentError, "invalid PSN online ID: #{online_id.inspect}"`. Guard against `nil` before calling
    `match?`.
  - `search` posts the body and returns it untouched.
  - `account_id` calls `search`, then uses `dig('domainResponses', 0, 'results') || []`, then `find` with `casecmp?`.
    Add the RBS file.

- [ ] **Step 4: Run the full suite.**
  Run: `bundle exec rake`
  Expected: it passes with no offences.

- [ ] **Step 5: Commit.**
  `git add lib sig spec && git commit -m "Add Users requests: search, account ID lookup, profiles, played games"`

### Task 4: `PSN::Client::Account`

**Files:**
- Create: `lib/psn/client/account.rb`, `sig/psn/client/account.rbs`, `spec/psn/client/account_spec.rb`
- Modify: `lib/psn/client.rb` (add `require_relative 'client/account'`)

**Interfaces:**
- Consumes: `Request#get(path, host:, params:)` and
  `Request#graphql(operation_name, variables, sha256_hash, host:, headers:)`
- Produces:
  - `Account.new(access_token)`
  - `#devices -> untyped`
  - `#library(limit: 100) -> untyped`
  - `#purchased_games(size: 200, start: 0) -> untyped`
  - `#summary -> untyped`
- Constants (exact values from the spec):
  - `DEVICES_PATH = '/api/v1/devices/accounts/me'`, on the `:dms` host
  - `DEVICES_PARAMS = { 'includeFields' => 'device,systemData', 'platform' => 'PS5,PS4,PS3,PSVita' }`
  - `LIBRARY_OPERATION = 'getUserGameList'`
  - `LIBRARY_HASH = 'e0136f81d7d1fb6be58238c574e9a46e1c0cc2f7f6977a08a5a46f224523a004'`
  - `LIBRARY_CATEGORIES = 'ps4_game,ps5_native_game'`
  - `LIBRARY_MAX_LIMIT = 100`
  - `PURCHASED_OPERATION = 'getPurchasedGameList'`
  - `PURCHASED_HASH = '827a423f6a8ddca4107ac01395af2ec0eafd8396fc7fa204aaf9b7ed2eefa168'`
  - `PURCHASED_VARIABLES = { 'isActive' => true, 'platform' => %w[ps4 ps5], 'sortBy' => 'ACTIVE_DATE', 'sortDirection' => 'desc' }`
  - `SUMMARY_OPERATION = 'getProfileOracle'`
  - `SUMMARY_HASH = 'fc0d765f537f3dce3e0d91c71e85daa401042ba43066acde9f8f584faced10df'`
  - `SUMMARY_HEADERS = { 'apollographql-client-name' => 'oracle' }`, on the `:web` host. Without this
    header the call returns HTTP 400 "Cannot query field" (verified live on 2026-07-11).

- [ ] **Step 1: Write the failing tests.** Stub `Request` as in Task 3:

```ruby
it 'fetches devices from the DMS host' do
  allow(request).to receive(:get).with('/api/v1/devices/accounts/me', host: :dms, params: described_class::DEVICES_PARAMS).and_return(body)
  expect(account.devices).to eq(body)
end
it 'fetches the library' do
  allow(request).to receive(:graphql).with('getUserGameList', { 'categories' => 'ps4_game,ps5_native_game', 'limit' => 100 },
                                           described_class::LIBRARY_HASH).and_return(body)
  expect(account.library).to eq(body)
end
it('rejects a library limit over 100') { expect { account.library(limit: 101) }.to raise_error(ArgumentError) }
it 'fetches purchased games' do
  allow(request).to receive(:graphql).with('getPurchasedGameList',
                                           described_class::PURCHASED_VARIABLES.merge('size' => 50, 'start' => 10),
                                           described_class::PURCHASED_HASH).and_return(body)
  expect(account.purchased_games(size: 50, start: 10)).to eq(body)
end
it 'fetches the summary from the web host with the oracle header' do
  allow(request).to receive(:graphql).with('getProfileOracle', {}, described_class::SUMMARY_HASH,
                                           host: :web, headers: { 'apollographql-client-name' => 'oracle' }).and_return(body)
  expect(account.summary).to eq(body)
end
```

- [ ] **Step 2: Run the tests to confirm they fail.**
  Run: `bundle exec rspec spec/psn/client/account_spec.rb`
  Expected: FAIL with `uninitialized constant PSN::Client::Account`.

- [ ] **Step 3: Implement `lib/psn/client/account.rb` and its RBS as specified.**

- [ ] **Step 4: Run the full suite.**
  Run: `bundle exec rake`
  Expected: it passes with no offences.

- [ ] **Step 5: Commit.**
  `git add lib sig spec && git commit -m "Add Account requests: devices, library, purchased games, summary"`

### Task 5: Live check script, README, CHANGELOG

**Files:**
- Create: `bin/verify_users.rb` (executable, modelled on `bin/verify_trophies.rb`)
- Modify: `README.md` (usage section), `CHANGELOG.md` (`[Unreleased]`)

**Interfaces:**
- Consumes: `Auth.authenticate`, plus every public method from Tasks 3 and 4

- [ ] **Step 1: Write `bin/verify_users.rb`.** It authenticates and then, wrapping each call so that one
  failure doesn't stop the rest:
  - calls `Account#summary` and prints the online ID and account ID from
    `data.oracleUserProfileRetrieve`
  - calls `Users#search` and `Users#account_id` with that online ID, and prints the result count and
    whether the ID matches
  - calls `Users#profile`, `Users#profile_by_account_id`, `Users#played_games(limit: 5)`,
    `Account#devices`, `Account#library(limit: 5)` and `Account#purchased_games(size: 5)`
  - prints a one-line count or key summary for each, and `FAILED: <class>: <message>` for any error

  Run `chmod +x bin/verify_users.rb`.

- [ ] **Step 2: Check that it loads without credentials.**
  Run: `bundle exec ruby -c bin/verify_users.rb && bundle exec rubocop bin/verify_users.rb`
  Expected: `Syntax OK` and no offences. A live run needs the user's `PSN_*` env vars. If they're set,
  run `bundle exec ruby bin/verify_users.rb` and report the output. If not, say it wasn't run.

- [ ] **Step 3: Update the docs.**
  - **README:** add "User data" and "Signed-in account" subsections after "Trophy data", in the same
    code-block style. Cover every new method, `PrivacyError`, and the note that these are undocumented
    Sony endpoints.
  - **CHANGELOG:** under `[Unreleased]`, add one bullet each for `Users`, `Account`, `PrivacyError`, and
    `Request` multi-host/POST/GraphQL support.

- [ ] **Step 4: Run the full suite.**
  Run: `bundle exec rake`
  Expected: it passes with no offences.

- [ ] **Step 5: Commit.**
  `git add bin/verify_users.rb README.md CHANGELOG.md && git commit -m "Document user and account requests; add live check script"`
