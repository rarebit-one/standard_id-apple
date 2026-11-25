# frozen_string_literal: true

# Offers the plugin's env vars to standard_health without depending on it.
# The block runs only when standard_health is loaded (it fires
# `run_load_hooks(:standard_health, ...)`), whichever gem loads first; without
# standard_health it never runs. It receives standard_health's contribution
# registry, of which only `contribute_env_vars` is used here.
#
# The provider stays off until apple_client_id is set, so nothing here is
# required unconditionally: the signing triple (APPLE_PRIVATE_KEY, APPLE_KEY_ID,
# APPLE_TEAM_ID) becomes required only once the provider is on and the app
# leaves the field to its ENV fallback, exactly when StandardId's boot check
# would report it missing. An app that declares any of these vars in its own
# env_spec overrides the row here.
ActiveSupport.on_load(:standard_health) do |health|
  apple = StandardId::Providers::Apple

  # Whether +field+ is left to its ENV fallback: the app never assigned it
  # (standard_id < 0.43 can't tell, so it counts as unassigned) and no
  # deprecated name is supplying it. An app that assigns the field, from
  # credentials say, needs no ENV var for it.
  legacy_env = { apple_private_key: apple::LEGACY_PRIVATE_KEY_ENV }
  from_env = lambda do |field|
    social = StandardId.config.social
    assigned = social.respond_to?(:assigned?) && social.assigned?(field)
    !assigned && (legacy_env[field].nil? || ENV[legacy_env[field]].blank?)
  end

  health.contribute_env_vars "standard_id-apple" do
    recommended :APPLE_CLIENT_ID,
      description: "Sign in with Apple web Services ID (social.apple_client_id). Setting it switches the provider " \
                   "on and makes the APPLE_PRIVATE_KEY / APPLE_KEY_ID / APPLE_TEAM_ID triple required; unset " \
                   "leaves the provider off"
    recommended :APPLE_MOBILE_CLIENT_ID,
      description: "App bundle ID for native Sign in with Apple (social.apple_mobile_client_id). Only apps with an " \
                   "iOS client need it; the native id_token flow is verified against Apple's JWKS, so it needs no " \
                   "signing key"
    recommended :APPLE_REDIRECT_URI, if: -> { apple.enabled? },
      description: "Return URL for a web-flow code exchanged without one (social.apple_redirect_uri), e.g. Android " \
                   "signing in through Apple's web flow via the API callback. Optional otherwise"
    required :APPLE_PRIVATE_KEY, if: -> { apple.enabled? && from_env.call(:apple_private_key) },
      description: "Apple EC private key (PEM) that signs the client_secret JWT (social.apple_private_key). A " \
                   "secret. Required once APPLE_CLIENT_ID switches the provider on, unless the app assigns the " \
                   "field itself; without it the callback fails after the user has authenticated with Apple. " \
                   "Replaces the deprecated APPLE_PRIVATE_KEY_PEM"
    required :APPLE_KEY_ID, if: -> { apple.enabled? && from_env.call(:apple_key_id) },
      description: "Key ID (kid) of the Apple private key (social.apple_key_id). Required once APPLE_CLIENT_ID " \
                   "switches the provider on, unless the app assigns the field itself"
    required :APPLE_TEAM_ID, if: -> { apple.enabled? && from_env.call(:apple_team_id) },
      description: "Apple Developer Team ID, the client_secret JWT's issuer (social.apple_team_id). Required once " \
                   "APPLE_CLIENT_ID switches the provider on, unless the app assigns the field itself"
  end
end
