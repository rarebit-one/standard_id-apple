# StandardId Apple Provider

This gem packages the StandardId Apple Sign In provider so the base `standard_id` gem no longer needs to ship Apple-specific logic or dependencies. Installations that require Apple login can opt-in by adding this gem.

## Installation

Add the gem next to `standard_id`:

```ruby
# Gemfile
gem "standard_id"
gem "standard_id_apple"
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
  config.social.apple_client_id = ENV["APPLE_CLIENT_ID"]
  config.social.apple_mobile_client_id = ENV["APPLE_MOBILE_CLIENT_ID"] # optional
  config.social.apple_team_id = ENV["APPLE_TEAM_ID"]
  config.social.apple_key_id = ENV["APPLE_KEY_ID"]
  config.social.apple_private_key = ENV["APPLE_PRIVATE_KEY_PEM"]
end
```

With those values in place, StandardId routes such as `/auth/callback/apple` continue to function using this provider gem.

## Testing

Run the spec suite:

```bash
bundle exec rspec
```

Tests stub Apple endpoints with `webmock` and mirror the expectations that previously lived in the core StandardId repository.

## Development

1. `bin/setup`
2. `bundle exec rspec`

To release:

1. Update `lib/standard_id_apple/version.rb`.
2. `bundle exec rake release`

## License

MIT — see [LICENSE.txt](LICENSE.txt).
