# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Requires Rails 8.1** (`activesupport >= 8.1`, was `>= 8.0`). Every
  consumer app already runs 8.1; 8.0 was never exercised in CI.

## [0.6.0] - 2026-09-24

Adopts the provider-plugin API of standard_id 0.42.

### Upgrade

- **Requires `standard_id` 0.42** (`~> 0.42`, was `>= 0.29, < 1.0`). Bump both
  together.
- **Rename `APPLE_PRIVATE_KEY_PEM` to `APPLE_PRIVATE_KEY`** when convenient.
  Initializers from the 0.5.0 generator assign `ENV["APPLE_PRIVATE_KEY_PEM"]`
  explicitly and keep working unchanged; the old name is also read as a
  deprecated ENV fallback (see Deprecated).
- **Expect a boot warning if Apple is half-configured.** With
  `apple_client_id` set and any of `apple_team_id` / `apple_key_id` /
  `apple_private_key` blank, standard_id now logs a warning at boot (raises in
  production under `c.social.provider_misconfiguration = :raise`). sidekick-web
  can drop the gated `APPLE_PRIVATE_KEY` / `APPLE_KEY_ID` / `APPLE_TEAM_ID`
  entries in `config/initializers/standard_health.rb` in favour of that
  setting, or keep them for the health report.
- **Anyone rescuing on message text:** several messages changed (see Changed).
  `StandardId::Apple::Railtie` no longer exists.

### Added

- **Required config fields.** `apple_private_key`, `apple_key_id` and
  `apple_team_id` are declared `required: true`, so
  `StandardId::Providers::Apple.configuration_errors` and standard_id's boot
  check report them whenever `apple_client_id` (the enabling field) is set —
  the two-stage check sidekick-web rebuilt by hand. `apple_mobile_client_id`
  stays optional: the native `id_token` flow needs no signing key.
- **ENV fallback** through standard_id 0.42: `APPLE_CLIENT_ID`,
  `APPLE_MOBILE_CLIENT_ID`, `APPLE_PRIVATE_KEY`, `APPLE_KEY_ID`, `APPLE_TEAM_ID`.
- **JWKS caching.** Apple's key set is cached in-process for an hour
  (`JWKS_CACHE_TTL`) instead of being downloaded on every sign-in. A token whose
  `kid` is not in the cached set triggers one refetch — Apple rotated — no more
  than once a minute (`JWKS_MIN_REFRESH_INTERVAL`), so tokens with made-up
  `kid`s cannot make this process hammer Apple. `reset_jwks_cache!` drops it.
- Specs for `resolve_params`, `skip_csrf?`, `supports_mobile_callback?` /
  `flow_for`, nonce handling, JWKS caching and configuration, plus standard_id's
  `"a registered StandardId provider"` shared example.

### Changed

- **The JWKS is fetched through `StandardId::HttpClient`** — 5s open / 10s read
  timeouts and the private/internal-address guard — instead of a bare
  `Net::HTTP.get_response` with Ruby's default 60s timeouts. HttpClient has no
  public plain GET, so this calls its `validate_url!` / `start_connection`
  directly; CI's compat job catches it if those change.
- **Nonce mismatches no longer leak the nonce.** The message was
  `ID token nonce mismatch. Expected: <nonce>, got: <nonce>`; it is now
  standard_id's `ID token nonce mismatch`, and the comparison is constant-time.
- **The duplicated helpers are gone** in favour of standard_id's
  `Providers::Base`: `rescue_to_oauth_error`, `verify_nonce!`,
  `build_authorization_url`, `extract_tokens` (the private
  `extract_token_payload` is removed). `lib/standard_id/apple/railtie.rb` is
  replaced by `StandardId::Providers.plugin_railtie(:apple, ...)`.
- **Error messages**, now consistently Apple-prefixed and never echoing a `kid`
  or nonce:
  - `Either code or id_token must be provided` → `Apple sign-in requires a code or an id_token`
  - `Access token login flow is not supported for Apple` → `Apple sign-in does not support the access token flow`
  - `Missing authorization code` → `Apple authorization code is missing`
  - `Missing id_token` → `Apple id_token is missing`
  - `Apple response missing id_token` → `Apple token response is missing id_token`
  - `Apple OAuth credentials are incomplete` → `... are incomplete: <fields> not set`
  - `Failed to exchange Apple authorization code: <error>` now falls back to
    `HTTP <status>` when Apple's body names no error (it printed nothing).
  - `JWK with kid '<kid>' not found in Apple's JWKS` → `Invalid Apple ID token: signing key not found in Apple's JWKS`
  - `Failed to fetch JWK: ...` → `Failed to fetch Apple JWKS: ...`. A non-2xx
    JWKS response is now `StandardId::OAuthError` (an upstream failure) rather
    than `InvalidRequestError`.
- Install generator and README use the canonical `APPLE_PRIVATE_KEY`, and
  document the ENV fallback, required fields and flows.

### Deprecated

- **`APPLE_PRIVATE_KEY_PEM`** as an ENV source for `apple_private_key`. Read only
  when the field is never assigned and `APPLE_PRIVATE_KEY` is unset, with one
  warning per process through `StandardId.deprecator`.

### Removed

- `StandardId::Apple::Railtie` (replaced by the Railtie `plugin_railtie`
  defines, `StandardId::Providers::Railties::Apple`).

## [0.5.0] - 2026-07-31

### Added

- **Install generator: `bin/rails g standard_id:apple:install`.** Writes
  `config/initializers/standard_id_apple.rb` with all five `social.apple_*`
  fields wired to ENV, then prints the environment variables the host has to
  set (including the warning that `APPLE_PRIVATE_KEY_PEM` is multi-line and
  that a secret store which flattens it to literal `\n` produces a key that
  parses but fails to sign — surfacing as a JWT error at callback time, not at
  boot). Idempotent: re-running skips an existing initializer; `--force`
  overwrites, `--skip-initializer` writes nothing.

  It writes a **separate** file rather than editing `standard_id.rb`, so the
  provider can be removed by deleting one file and `standard_id`'s own install
  generator stays free to overwrite its initializer without clobbering these
  credentials. Initializers load alphabetically, so the base config is applied
  first. The generated file uses the `config.social.` form throughout — a spec
  pins that it never emits the unqualified `config.apple_*` form, which works
  today only because the names happen to be unique across scopes.

  Five of the nine `standard_*` gems shipped an install generator and this was
  not one of them, which left both consumers assembling the block from the
  README by hand.

### Documentation

- **Consumer list corrected in `CLAUDE.md`: this gem has two consumers, not
  one.** It named `luminality-web` only; `sidekick-web` also consumes it. Both
  live in sibling workspaces rather than beside this repo, which is how the
  second one went unnoticed.

- **Corrected the Configuration section, which was wrong in two ways.**

  It showed the *flat* form (`config.apple_client_id = ...`) rather than the
  `social` scope the fields actually live in. The flat form works — StandardId
  routes an unqualified name to the owning scope when it is unique across scopes
  — but only once the field is declared, and it silently breaks the day another
  scope declares a colliding name. Existing code using it is not broken.

  It also documented a form that raised on `standard_id` <= 0.32.0. These fields
  are declared by this gem, and until `standard_id` 0.33.0 they were declared
  from this gem's Railtie `after_initialize` — after `config/initializers` — so
  the plain initializer raised `StandardId::ConfigurationError: Unknown field
  'apple_client_id' for scope 'social'`. The README now records the
  `after_initialize` workaround for older `standard_id`, states that 0.33.0
  declares provider fields before `:load_config_initializers` so the plain form
  is correct there, and notes that the fields do not exist at all without this
  gem in the Gemfile — on any `standard_id` version.

### Changed

- **`standard_id` dependency tightened from `~> 0.1, >= 0.1.7` to `~> 0.29.0`.**
  The old constraint claimed compatibility with every `0.x` release while this
  plugin reaches into `StandardId::ProviderRegistry` and
  `StandardId::Providers::Apple`, and `standard_id` is pre-1.0 with breaking
  minors. Bundler would happily resolve against an untested minor and fail at
  runtime instead of at resolution. Both current consumers already pin
  `standard_id "~> 0.29.0"`, so nothing existing is affected.

### Fixed

- Gemspec now uses an allow-list (`Dir["lib/**/*", …]`) rather than a
  `git ls-files` reject-list. A reject-list fails **open** — new files ship
  unless someone remembers to exclude them, which is how `.claude/` reached
  published `0.3.0` of `standard_id-google` (rarebit-one/standard_id-google#69).
  Drops `.editorconfig`, `.pinact.yaml`, `.rspec`, `.rubocop.yml`,
  `.ruby-version`, `AGENTS.md`, `CLAUDE.md`, and `CODE_OF_CONDUCT.md` from the
  package; `lib/` is byte-identical.

## [0.4.0] - 2026-05-19

### Changed

- Relaxed `jwt` dependency constraint from `~> 2.7` to `>= 2.7, < 4`, allowing consumers to satisfy the GHSA security advisory for `jwt` 2.x by upgrading to `jwt` 3.x. The provider's `JWT.encode` / `JWT.decode` call sites already pass an explicit algorithm and are compatible with the 3.x API surface.

## [0.3.0] - 2026-04-29

### Added

- `.editorconfig` and `AGENTS.md` for dev tooling parity with the parent `standard_id` gem.
- SimpleCov branch coverage reporting in `spec/spec_helper.rb`. No minimum threshold is enforced; `coverage/` is gitignored.

### Changed

- CI and release workflows migrated to the shared `rarebit-one/.github` reusable workflows (`reusable-gem-ci.yml@v1`, `reusable-gem-release.yml@v1`); `.github/workflows/ci.yml` and `release.yml` are now thin shims.
- CI matrix expanded to all four Ruby 4.0.x patch releases (`4.0.0`, `4.0.1`, `4.0.2`, `4.0.3`) and lint pinned to `4.0.3`. Branch protection will be updated post-merge to require the consolidated `ci / test` aggregator (added in `rarebit-one/.github#6`) instead of per-version checks, so future Ruby version churn won't require updating protection.

### Removed

- **BREAKING:** Dropped support for Ruby < 4.0. `required_ruby_version` is now `>= 4.0`. Aligns with `standard_id` (the parent gem) which made the same break in [rarebit-one/standard_id#195](https://github.com/rarebit-one/standard_id/pull/195) — host apps must upgrade to Ruby 4.0+ before bundling this version.

## [0.2.0] - 2026-04-21

### Added

- Auto-register provider with StandardId via `Rails::Railtie` on `config.after_initialize`, so apps that bundle the gem no longer need an explicit initializer (#30)

## [0.1.2] - 2026-01-13

### Added

- Support nonce and passing custom parameters to Apple Sign In (#2)

## [0.1.1] - 2025-12-24

### Changed

- Standardized config access patterns

## [0.1.0] - 2025-12-20

### Added

- Initial release of Apple Sign In provider plugin for StandardId
