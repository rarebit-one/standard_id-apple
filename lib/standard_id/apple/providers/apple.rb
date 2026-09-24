require "json"
require "jwt"
require "net/http"
require "openssl"

module StandardId
  module Providers
    class Apple < Base
      ISSUER = "https://appleid.apple.com".freeze
      AUTH_ENDPOINT = "#{ISSUER}/auth/authorize".freeze
      TOKEN_ENDPOINT = "#{ISSUER}/auth/token".freeze
      JWKS_URI = "#{ISSUER}/auth/keys".freeze
      DEFAULT_SCOPE = "name email".freeze
      DEFAULT_RESPONSE_MODE = "form_post".freeze
      AUTHORIZATION_PARAM_DEFAULTS = {
        scope: DEFAULT_SCOPE,
        response_mode: DEFAULT_RESPONSE_MODE
      }.freeze

      # Apple's signing keys rotate rarely; an unknown `kid` forces an early
      # refetch (see #fetch_jwk), so a long TTL costs nothing on rotation.
      JWKS_CACHE_TTL = 3600
      # Floor between forced refetches, so a stream of ID tokens carrying
      # made-up `kid`s cannot turn this process into a request amplifier
      # against Apple.
      JWKS_MIN_REFRESH_INTERVAL = 60

      # Pre-0.6.0 install generators wired `apple_private_key` to this
      # variable. Still read, with a deprecation warning, when the canonical
      # APPLE_PRIVATE_KEY is unset and the host never assigns the field.
      LEGACY_PRIVATE_KEY_ENV = "APPLE_PRIVATE_KEY_PEM".freeze

      @jwks_mutex = Mutex.new
      @jwks_cache = nil

      class << self
        def provider_name
          "apple"
        end

        def supported_authorization_params
          [:nonce, :scope, :response_mode]
        end

        def authorization_url(state:, redirect_uri:, **options)
          ensure_basic_credentials!

          build_authorization_url(
            endpoint: AUTH_ENDPOINT,
            client_id: StandardId.config.apple_client_id,
            redirect_uri:, state:, options:,
            defaults: AUTHORIZATION_PARAM_DEFAULTS
          )
        end

        def get_user_info(code: nil, id_token: nil, access_token: nil, redirect_uri: nil, nonce: nil, **options)
          client_id = options[:client_id] || StandardId.config.apple_client_id

          if id_token.present?
            build_response(
              verify_id_token(id_token: id_token, client_id: client_id, nonce: nonce),
              tokens: { id_token: id_token }
            )
          elsif code.present?
            exchange_code_for_user_info(code: code, redirect_uri: redirect_uri, client_id: client_id, nonce: nonce)
          elsif access_token.present?
            raise StandardId::InvalidRequestError, "Apple sign-in does not support the access token flow"
          else
            raise StandardId::InvalidRequestError, "Apple sign-in requires a code or an id_token"
          end
        end

        # `apple_client_id` (the web Services ID) switches the provider on —
        # it is the enabling field, so StandardId's boot check reports the
        # three signing credentials below whenever it is set. They are what
        # the code exchange needs to sign its client_secret; without them the
        # web flow starts fine and only fails at the callback, after the user
        # has authenticated with Apple.
        #
        # `apple_mobile_client_id` gates nothing: the native id_token flow
        # verifies against Apple's JWKS and needs no signing key.
        #
        # ENV fallbacks (standard_id >= 0.42) use the upper-cased field names:
        # APPLE_CLIENT_ID, APPLE_MOBILE_CLIENT_ID, APPLE_PRIVATE_KEY,
        # APPLE_KEY_ID, APPLE_TEAM_ID.
        def config_schema
          {
            apple_client_id: { type: :string, default: nil },
            apple_mobile_client_id: { type: :string, default: nil },
            apple_private_key: { type: :string, default: -> { legacy_private_key_from_env }, required: true },
            apple_key_id: { type: :string, default: nil, required: true },
            apple_team_id: { type: :string, default: nil, required: true }
          }
        end

        def default_scope
          DEFAULT_SCOPE
        end

        # Apple posts the web callback (response_mode=form_post).
        def skip_csrf?
          true
        end

        # Android and other non-Apple platforms sign in through Apple's web
        # flow and need the server to redirect back into the app.
        def supports_mobile_callback?
          true
        end

        # The web flow authenticates against the Services ID, the native flow
        # against the app's bundle ID.
        def resolve_params(params, context: {})
          flow = context[:flow] || :web
          client_id = flow == :mobile ? StandardId.config.apple_mobile_client_id : StandardId.config.apple_client_id

          params.merge(client_id: client_id)
        end

        def exchange_code_for_user_info(code:, redirect_uri:, client_id: StandardId.config.apple_client_id, nonce: nil)
          rescue_to_oauth_error do
            ensure_full_credentials!(client_id: client_id)
            raise StandardId::InvalidRequestError, "Apple authorization code is missing" if code.blank?

            token_response = HttpClient.post_form(TOKEN_ENDPOINT, {
                                                    client_id: client_id,
                                                    client_secret: generate_client_secret(client_id: client_id),
                                                    code: code,
                                                    grant_type: "authorization_code",
                                                    redirect_uri: redirect_uri
                                                  })

            unless token_response.is_a?(Net::HTTPSuccess)
              raise StandardId::InvalidRequestError,
                    "Failed to exchange Apple authorization code: #{error_reason(token_response)}"
            end

            parsed_token = JSON.parse(token_response.body)
            id_token = parsed_token["id_token"]
            raise StandardId::InvalidRequestError, "Apple token response is missing id_token" if id_token.blank?

            user_info = verify_id_token(id_token: id_token, client_id: client_id, nonce: nonce)
            build_response(user_info, tokens: extract_tokens(parsed_token))
          end
        end

        def verify_id_token(id_token:, client_id: StandardId.config.apple_client_id, nonce: nil)
          rescue_to_oauth_error do
            raise StandardId::InvalidRequestError, "Apple id_token is missing" if id_token.blank?
            raise StandardId::InvalidRequestError, "Apple client_id is not configured" if client_id.blank?

            _unverified_payload, header = JWT.decode(id_token, nil, false)
            jwk = fetch_jwk(kid: header["kid"])

            verified_payload, = JWT.decode(
              id_token,
              jwk.public_key,
              true,
              algorithms: ["RS256"],
              iss: ISSUER,
              verify_iss: true,
              aud: client_id,
              verify_aud: true
            )

            # Web flow with a server-generated nonce; constant-time, and the
            # error never echoes either value.
            verify_nonce!(expected: nonce, actual: verified_payload["nonce"])

            {
              "sub" => verified_payload["sub"],
              "email" => verified_payload["email"],
              "email_verified" => verified_payload["email_verified"],
              "is_private_email" => verified_payload["is_private_email"]
            }.compact
          rescue JWT::InvalidAudError => e
            raise StandardId::InvalidRequestError, "Invalid Apple ID token audience: #{e.message}"
          rescue JWT::DecodeError => e
            raise StandardId::InvalidRequestError, "Invalid Apple ID token: #{e.message}"
          end
        end

        # Drop the in-process JWKS cache (tests, or after a known rotation).
        def reset_jwks_cache!
          @jwks_mutex.synchronize { @jwks_cache = nil }
        end

        private

        def ensure_basic_credentials!(client_id: StandardId.config.apple_client_id)
          return if client_id.present?

          raise StandardId::InvalidRequestError, "Apple OAuth is not configured"
        end

        # The same fields StandardId's boot check reports (required_config_fields),
        # checked again at the point of use because the mobile code exchange
        # can run with only apple_mobile_client_id set. Names fields, never
        # values.
        def ensure_full_credentials!(client_id: nil)
          ensure_basic_credentials!(client_id: client_id)

          missing = required_config_fields.select { |field| config_value(field).blank? }
          return if missing.empty?

          raise StandardId::InvalidRequestError,
                "Apple OAuth credentials are incomplete: #{missing.join(', ')} not set"
        end

        def generate_client_secret(client_id: StandardId.config.apple_client_id)
          header = {
            alg: "ES256",
            kid: StandardId.config.apple_key_id
          }

          payload = {
            iss: StandardId.config.apple_team_id,
            iat: Time.current.to_i,
            exp: Time.current.to_i + 3600,
            aud: ISSUER,
            sub: client_id
          }

          private_key = OpenSSL::PKey::EC.new(StandardId.config.apple_private_key)
          JWT.encode(payload, private_key, "ES256", header)
        end

        # Look `kid` up in Apple's JWKS, served from an in-process cache
        # (JWKS_CACHE_TTL). An unknown `kid` refetches once — Apple may have
        # rotated — subject to JWKS_MIN_REFRESH_INTERVAL.
        def fetch_jwk(kid:)
          raise StandardId::InvalidRequestError, "Invalid Apple ID token: header has no kid" if kid.blank?

          jwk_data = find_jwk(jwks_keys, kid) || find_jwk(jwks_keys(refresh: true), kid)
          raise StandardId::InvalidRequestError, "Invalid Apple ID token: signing key not found in Apple's JWKS" unless jwk_data

          JWT::JWK.import(jwk_data)
        end

        def find_jwk(keys, kid)
          keys.find { |key| key["kid"] == kid }
        end

        def jwks_keys(refresh: false)
          @jwks_mutex.synchronize do
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            cache = @jwks_cache

            stale = cache.nil? || now - cache[:fetched_at] > JWKS_CACHE_TTL
            forced = refresh && cache && now - cache[:fetched_at] >= JWKS_MIN_REFRESH_INTERVAL
            if stale || forced
              @jwks_cache = cache = { keys: download_jwks, fetched_at: now }
            end

            cache[:keys]
          end
        end

        # Fetched through StandardId::HttpClient's connection setup, so the
        # request gets its timeouts and its private/internal-address guard.
        # HttpClient has no public plain GET (only get_with_bearer, which would
        # send an empty Authorization header), hence the two private calls.
        def download_jwks
          rescue_to_oauth_error("Failed to fetch Apple JWKS") do
            uri, resolved_ip = HttpClient.send(:validate_url!, JWKS_URI)
            response = HttpClient.send(:start_connection, uri, resolved_ip: resolved_ip) do |http|
              http.request(Net::HTTP::Get.new(uri))
            end
            raise StandardId::OAuthError, "Failed to fetch Apple JWKS: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            keys = JSON.parse(response.body)["keys"]
            raise StandardId::OAuthError, "Failed to fetch Apple JWKS: response has no keys" unless keys.is_a?(Array)

            keys
          end
        end

        def error_reason(response)
          body = JSON.parse(response.body.to_s)
          reason = body["error"] if body.is_a?(Hash)
          reason.presence || "HTTP #{response.code}"
        rescue JSON::ParserError
          "HTTP #{response.code}"
        end

        def legacy_private_key_from_env
          value = ENV[LEGACY_PRIVATE_KEY_ENV]
          return nil if value.blank?

          # An unassigned field's default is re-evaluated on read; warn once.
          return value if @legacy_private_key_warned

          @legacy_private_key_warned = true
          StandardId.deprecator.warn(
            "standard_id-apple: reading apple_private_key from #{LEGACY_PRIVATE_KEY_ENV} is deprecated. " \
            "Rename the variable to APPLE_PRIVATE_KEY (or assign config.social.apple_private_key explicitly)."
          )
          value
        end
      end
    end
  end
end
