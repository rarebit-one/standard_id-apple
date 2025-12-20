# frozen_string_literal: true

source "https://rubygems.org"

ruby file: ".ruby-version"

# Specify your gem"s dependencies in standard_id_apple.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

group :development, :test do
  gem "rspec", "~> 3.0"
  gem "webmock", "~> 3.26"

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end
