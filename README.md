# StandardId Apple Provider

This gem extracts the Apple OAuth provider from the core [`standard_id`](https://github.com/rarebit-one/standard_id) engine so installations can opt into Apple login independently of the base gem.

## Installation

Requires `standard_id` 0.42 or later. Add the gem next to `standard_id`:

```ruby
# Gemfile
gem "standard_id"
gem "standard_id-apple"
```

Then install:

```bash
bundle install
```

The gem automatically registers itself with StandardId when it is required.

Then run the install generator to drop the credentials block in place:

```bash
bin/rails g standard_id:apple:install
```

This writes `config/initializers/standard_id_apple.rb` — deliberately a
separate file from `config/initializers/standard_id.rb`, so the provider can be
removed by deleting one file and `standard_id`'s own install generator stays
free to overwrite its initializer without clobbering these values. Initializers
load alphabetically, so the base config is applied first. The generator is
idempotent; re-running on an existing initializer skips with a clear message
(pass `--force` to overwrite).

## Configuration

The generator writes this for you; the block is documented here for hosts
configuring by hand. Configure Apple credentials via the StandardId
configuration block, in the `social` scope:

```ruby
# config/initializers/standard_id_apple.rb
StandardId.configure do |config|
  config.social.apple_client_id = ENV["APPLE_CLIENT_ID"]
  config.social.apple_mobile_client_id = ENV["APPLE_MOBILE_CLIENT_ID"] # optional
  config.social.apple_team_id = ENV["APPLE_TEAM_ID"]
  config.social.apple_key_id = ENV["APPLE_KEY_ID"]
  config.social.apple_private_key = ENV["APPLE_PRIVATE_KEY"]
end
```

With those values in place, StandardId routes such as `/auth/callback/apple` continue to function using this provider gem.

### ENV fallback

On `standard_id` 0.42+, a field you never assign falls back to the ENV
variable named after it, upper-cased:

| Field | ENV variable |
|---|---|
| `apple_client_id` | `APPLE_CLIENT_ID` |
| `apple_mobile_client_id` | `APPLE_MOBILE_CLIENT_ID` |
| `apple_team_id` | `APPLE_TEAM_ID` |
| `apple_key_id` | `APPLE_KEY_ID` |
| `apple_private_key` | `APPLE_PRIVATE_KEY` (deprecated fallback: `APPLE_PRIVATE_KEY_PEM`) |

So with those variables set the block above is optional. Explicit
configuration, even `nil`, always wins. `APPLE_PRIVATE_KEY_PEM` — the name
install generators before 0.6.0 wrote — is still read when
`APPLE_PRIVATE_KEY` is unset and the field is never assigned, with a
deprecation warning; rename it. (An initializer that assigns
`ENV["APPLE_PRIVATE_KEY_PEM"]` explicitly keeps working as-is.)

### Required fields and the boot check

`apple_client_id` (the web Services ID) switches the provider on — it is what
`StandardId.social_provider_enabled?(:apple)` and the `apple_enabled` Inertia
prop report. While it is set, `apple_team_id`, `apple_key_id` and
`apple_private_key` are required: the code exchange signs its `client_secret`
with them, so without them the flow starts, the user authenticates with Apple,
and only then does the callback fail. StandardId checks this once every plugin
has registered:

```ruby
StandardId::Providers::Apple.configuration_errors
# => ["apple_private_key is required when apple_client_id is set"]

config.social.provider_misconfiguration = :raise # fail a production boot instead of warning
```

`apple_mobile_client_id` gates nothing: the native `id_token` flow verifies the
token against Apple's JWKS and needs no signing key. A native-only app (mobile
client ID set, `apple_client_id` not) is therefore "not enabled" for the web
UI while its native sign-in keeps working.

### Flows

| Flow | Audience (`client_id`) | Needs signing key |
|---|---|---|
| Web (`/auth/callback/apple`, form_post, CSRF skipped) | `apple_client_id` | yes |
| Native `id_token` (`/api/oauth/callback/apple`) | `apple_mobile_client_id` | no |
| Web flow on Android etc. (`flow=web` on the API callback, redirects back into the app) | `apple_client_id` | yes |

Apple's signing keys (JWKS) are fetched through `StandardId::HttpClient`
(timeouts, private-address guard) and cached in-process for an hour; a token
signed with an unknown key triggers one early refetch, at most once a minute.

### Two corrections to earlier versions of this section

**The `social.` prefix.** This section previously showed the flat form
(`config.apple_client_id = ...`). That happens to work — `StandardId`'s top-level
config routes an unqualified name to the owning scope when it is unique across
scopes, and these five are — but only *after* the field has been declared, and it
is the wrong thing to document: the fields live in the `social` scope, the
install template writes them there, and the flat form silently stops working the
day another scope declares a colliding name. Existing code using the flat form is
not broken and needs no change.

**Boot ordering.** These fields are declared by *this gem*, not by
`standard_id`, and until `standard_id` 0.33.0 they were declared from this gem's
Railtie `after_initialize` — which runs *after* `config/initializers`. On
`standard_id` **0.32.0 and earlier**, the block above therefore raised:

```
StandardId::ConfigurationError: Unknown field 'apple_client_id' for scope 'social'
```

The workaround was to wrap the writes:

```ruby
# Only needed on standard_id <= 0.32.0
Rails.application.config.after_initialize do
  StandardId.configure { |config| config.social.apple_client_id = ENV["APPLE_CLIENT_ID"] }
end
```

`standard_id` **>= 0.33.0** declares every loaded provider's fields before
`:load_config_initializers`, so a plain initializer is correct. The wrapper is no
longer needed and existing ones keep working unchanged.

Note this is about *ordering*, not just versions: **the fields do not exist
without this gem in your Gemfile**, on any `standard_id` version. Configuring
`social.apple_*` with the plugin absent raises the same error, correctly.

## Testing

In a host app, pin the plugin's registration with standard_id's shared
example:

```ruby
require "standard_id/testing"

RSpec.describe "StandardId social providers" do
  it_behaves_like "a registered StandardId provider", :apple
end
```

Run this gem's spec suite:

```bash
bundle exec rspec
```

## Development

1. `bin/setup`
2. `bundle exec rspec`

To release a new version:

1. Update the version in `lib/standard_id/apple/version.rb`.
2. Run `bundle exec rake release` to tag, push, and publish to RubyGems.

## License

MIT — see [LICENSE](LICENSE).
