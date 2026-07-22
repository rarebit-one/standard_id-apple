# frozen_string_literal: true

require_relative "lib/standard_id/apple/version"

Gem::Specification.new do |spec|
  spec.name = "standard_id-apple"
  spec.version = StandardId::Apple::VERSION
  spec.authors = ["Jaryl Sim"]
  spec.email   = ["code@jaryl.dev"]

  spec.summary = "Apple Sign In provider plugin for the StandardId engine."
  spec.description = "Extracted StandardId::Providers::Apple implementation packaged as a standalone gem so StandardId installations can opt into Sign in with Apple independently."
  spec.homepage = "https://github.com/rarebit-one/standard_id_apple"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  # Allow-list, not a reject-list: only these paths ship. A reject-list fails
  # OPEN — anything new in the repo is published unless someone remembers to
  # exclude it, which is how `.claude/` leaked into 0.3.0 of the sibling gem
  # (see standard_id-google#69). Matches the rest of the standard_* family.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 8.0"
  spec.add_dependency "jwt", ">= 2.7", "< 4"
  # Pinned to the standard_id 0.29 series. This plugin reaches into internals
  # (StandardId::ProviderRegistry, StandardId::Providers::Apple), and standard_id
  # is pre-1.0 with breaking minors, so `~> 0.1` was claiming compatibility with
  # releases this gem has never been tested against. A hard resolution failure on
  # the next minor is the intended behaviour: it forces a compatibility check and
  # a plugin release instead of a runtime break in a consumer.
  spec.add_dependency "standard_id", "~> 0.29.0"
end
