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

Configure Apple credentials via the StandardId configuration block:

```ruby
StandardId.configure do |config|
  config.apple_client_id = ENV["APPLE_CLIENT_ID"]
  config.apple_mobile_client_id = ENV["APPLE_MOBILE_CLIENT_ID"] # optional
  config.apple_team_id = ENV["APPLE_TEAM_ID"]
  config.apple_key_id = ENV["APPLE_KEY_ID"]
  config.apple_private_key = ENV["APPLE_PRIVATE_KEY_PEM"]
end
```

With those values in place, StandardId routes such as `/auth/callback/apple` continue to function using this provider gem.

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
