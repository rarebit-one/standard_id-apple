# frozen_string_literal: true

require "rails/generators"

module StandardId
  module Apple
    module Generators
      # Installs the Apple provider's credentials block in a host Rails app.
      #
      # Writes `config/initializers/standard_id_apple.rb` — a separate file from
      # `config/initializers/standard_id.rb` on purpose. The provider is opt-in
      # per app, so its credentials should be removable by deleting one file,
      # and `standard_id`'s own install generator must stay free to overwrite
      # its initializer without clobbering these five values.
      #
      # Initializers load alphabetically, so `standard_id.rb` runs before
      # `standard_id_apple.rb` — the base configuration is already applied by
      # the time this file sets the `social.apple_*` fields.
      #
      # Idempotent: re-running skips an initializer that is already there.
      # `--skip-initializer` opts out; `--force` overwrites.
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        INITIALIZER_PATH = "config/initializers/standard_id_apple.rb"

        desc <<~DESC
          Installs StandardId Apple. This writes #{INITIALIZER_PATH} with the
          five social.apple_* fields wired to ENV, and prints the env vars the
          host needs to set.

          The generator is idempotent — an existing initializer is skipped with
          a clear message. Pass --force to overwrite.
        DESC

        class_option :skip_initializer, type: :boolean, default: false,
          desc: "Do not write #{INITIALIZER_PATH}"
        class_option :force, type: :boolean, default: false,
          desc: "Overwrite #{INITIALIZER_PATH} if it already exists"

        def copy_initializer
          if options[:skip_initializer]
            say_status("skip", "#{INITIALIZER_PATH} (--skip-initializer)", :yellow)
            return
          end

          if File.exist?(File.join(destination_root, INITIALIZER_PATH)) && !options[:force]
            say_status("identical", "#{INITIALIZER_PATH} (already exists; pass --force to overwrite)", :blue)
            return
          end

          template "initializer.rb.erb", INITIALIZER_PATH, force: options[:force]
        end

        def print_env_hint
          return if options[:skip_initializer]

          say ""
          say "=" * 79
          say "StandardId Apple installed."
          say ""
          say "Set these in the host's environment (1Password / DO app spec / .env):"
          say ""
          say "  APPLE_CLIENT_ID         the Services ID (web sign-in)"
          say "  APPLE_MOBILE_CLIENT_ID  the iOS bundle ID — optional, web-only apps skip it"
          say "  APPLE_TEAM_ID           the 10-character Apple Developer team ID"
          say "  APPLE_KEY_ID            the key ID of the Sign In with Apple private key"
          say "  APPLE_PRIVATE_KEY_PEM   the .p8 private key contents, PEM, newlines intact"
          say ""
          say "APPLE_PRIVATE_KEY_PEM is multi-line. Most secret stores flatten it to"
          say "literal \\n — if sign-in fails on a JWT signing error, that is why."
          say "=" * 79
          say ""
        end
      end
    end
  end
end
