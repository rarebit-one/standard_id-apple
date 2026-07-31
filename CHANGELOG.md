# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
