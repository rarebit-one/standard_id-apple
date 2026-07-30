# StandardId Apple Provider

This gem extracts the Apple OAuth provider from the core [`standard_id`](https://github.com/rarebit-one/standard_id) engine so installations can opt into Apple login independently of the base gem.

## Installation

Add the gem next to `standard_id`:

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

## Configuration

Configure Apple credentials via the StandardId configuration block, in the
`social` scope:

```ruby
# config/initializers/standard_id.rb
StandardId.configure do |config|
  config.social.apple_client_id = ENV["APPLE_CLIENT_ID"]
  config.social.apple_mobile_client_id = ENV["APPLE_MOBILE_CLIENT_ID"] # optional
  config.social.apple_team_id = ENV["APPLE_TEAM_ID"]
  config.social.apple_key_id = ENV["APPLE_KEY_ID"]
  config.social.apple_private_key = ENV["APPLE_PRIVATE_KEY_PEM"]
end
```

With those values in place, StandardId routes such as `/auth/callback/apple` continue to function using this provider gem.

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

Run the spec suite:

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
