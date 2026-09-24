# frozen_string_literal: true

require "spec_helper"
require "openssl"

RSpec.describe StandardId::Providers::Apple do
  let(:apple_client_id) { "com.example.app" }
  let(:apple_team_id) { "TEAM123456" }
  let(:apple_key_id) { "KEY123456" }
  let(:apple_private_key) { OpenSSL::PKey::EC.generate("prime256v1").to_pem }
  let(:test_rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:test_kid) { "TEST_KID_123" }

  before do
    described_class.reset_jwks_cache!
    StandardId.config.apple_client_id = apple_client_id
    StandardId.config.apple_team_id = apple_team_id
    StandardId.config.apple_key_id = apple_key_id
    StandardId.config.apple_private_key = apple_private_key
  end

  after do
    StandardId.config.apple_client_id = nil
    StandardId.config.apple_team_id = nil
    StandardId.config.apple_key_id = nil
    StandardId.config.apple_private_key = nil
  end

  describe "interface compliance" do
    it "inherits from Base" do
      expect(described_class).to be < StandardId::Providers::Base
    end
  end

  describe ".provider_name" do
    it 'returns "apple"' do
      expect(described_class.provider_name).to eq("apple")
    end
  end

  describe ".default_scope" do
    it 'returns "name email"' do
      expect(described_class.default_scope).to eq("name email")
    end
  end

  describe ".authorization_url" do
    let(:redirect_uri) { "https://example.com/auth/apple/callback" }
    let(:state) { "random_state_string" }

    context "when credentials are configured" do
      it "generates the correct authorization URL" do
        url = described_class.authorization_url(
          state: state,
          redirect_uri: redirect_uri
        )

        uri = URI.parse(url)
        params = URI.decode_www_form(uri.query).to_h

        expect(uri.scheme).to eq("https")
        expect(uri.host).to eq("appleid.apple.com")
        expect(uri.path).to eq("/auth/authorize")
        expect(params["client_id"]).to eq(apple_client_id)
        expect(params["redirect_uri"]).to eq(redirect_uri)
        expect(params["response_type"]).to eq("code")
        expect(params["state"]).to eq(state)
        expect(params["scope"]).to eq("name email")
        expect(params["response_mode"]).to eq("form_post")
      end

      it "allows custom scope" do
        url = described_class.authorization_url(
          state: state,
          redirect_uri: redirect_uri,
          scope: "email"
        )

        params = URI.decode_www_form(URI(url).query).to_h
        expect(params["scope"]).to eq("email")
      end

      it "allows custom response_mode" do
        url = described_class.authorization_url(
          state: state,
          redirect_uri: redirect_uri,
          response_mode: "query"
        )

        params = URI.decode_www_form(URI(url).query).to_h
        expect(params["response_mode"]).to eq("query")
      end

      it "accepts multiple extra parameters" do
        url = described_class.authorization_url(
          state: state,
          redirect_uri: redirect_uri,
          nonce: "random_nonce_value",
          response_mode: "form_post"
        )

        expect(url).to include("nonce=random_nonce_value")
        expect(url).to include("response_mode=form_post")
      end
    end

    context "when client_id is not configured" do
      before { StandardId.config.apple_client_id = nil }

      it "raises an error" do
        expect do
          described_class.authorization_url(state: state, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError, /Apple OAuth is not configured/)
      end
    end
  end

  describe ".get_user_info" do
    context "with id_token" do
      let(:user_sub) { "001234.abcd1234abcd1234abcd1234abcd1234.1234" }
      let(:user_email) { "user@example.com" }

      it "verifies and returns user info from id_token" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email)
        stub_jwks_request

        result = described_class.get_user_info(id_token: id_token)

        expect(result[:user_info]["sub"]).to eq(user_sub)
        expect(result[:user_info]["email"]).to eq(user_email)
        expect(result[:tokens]).to eq({ id_token: id_token }.with_indifferent_access)
      end

      it "raises error when id_token is blank" do
        expect do
          described_class.get_user_info(id_token: "")
        end.to raise_error(StandardId::InvalidRequestError, /Apple sign-in requires a code or an id_token/)
      end
    end

    context "with authorization code" do
      let(:code) { "test_auth_code" }
      let(:redirect_uri) { "https://example.com/auth/apple/callback" }
      let(:user_sub) { "001234.abcd1234abcd1234abcd1234abcd1234.1234" }
      let(:user_email) { "user@example.com" }

      it "exchanges code for user info" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email)
        stub_token_exchange_request(code: code, id_token: id_token)
        stub_jwks_request

        result = described_class.get_user_info(code: code, redirect_uri: redirect_uri)

        expect(result[:user_info]["sub"]).to eq(user_sub)
        expect(result[:user_info]["email"]).to eq(user_email)
        expect(result[:tokens]).to include(:access_token, :id_token)
      end

      it "raises error when code is blank" do
        expect do
          described_class.get_user_info(code: "", redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError, /Apple sign-in requires a code or an id_token/)
      end
    end

    context "when neither code nor id_token is provided" do
      it "raises an error" do
        expect do
          described_class.get_user_info
        end.to raise_error(StandardId::InvalidRequestError, /Apple sign-in requires a code or an id_token/)
      end
    end
  end

  describe ".exchange_code_for_user_info" do
    let(:code) { "test_authorization_code" }
    let(:redirect_uri) { "https://example.com/auth/apple/callback" }
    let(:user_sub) { "001234.abcd1234abcd1234abcd1234abcd1234.1234" }
    let(:user_email) { "user@privaterelay.appleid.com" }

    context "with valid credentials" do
      it "exchanges authorization code for user info" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, is_private_email: true)
        stub_token_exchange_request(code: code, id_token: id_token)
        stub_jwks_request

        result = described_class.exchange_code_for_user_info(
          code: code,
          redirect_uri: redirect_uri
        )

        expect(result[:user_info]["sub"]).to eq(user_sub)
        expect(result[:user_info]["email"]).to eq(user_email)
        expect(result[:user_info]["is_private_email"]).to eq("true")
        expect(result[:tokens]).to include(
          access_token: "test_access_token",
          refresh_token: "test_refresh_token"
        )
        expect(result[:tokens]).to include(:id_token)
      end

      it "generates a valid client_secret JWT" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, is_private_email: true)
        stub_token_exchange_request(code: code, id_token: id_token)
        stub_jwks_request

        described_class.exchange_code_for_user_info(
          code: code,
          redirect_uri: redirect_uri
        )

        expect(WebMock).to(have_requested(:post, "https://appleid.apple.com/auth/token")
          .with do |req|
            body = URI.decode_www_form(req.body).to_h
            client_secret = body["client_secret"]

            decoded = JWT.decode(client_secret, nil, false)[0]
            expect(decoded["iss"]).to eq(apple_team_id)
            expect(decoded["aud"]).to eq("https://appleid.apple.com")
            expect(decoded["sub"]).to eq(apple_client_id)
            expect(decoded["exp"] - decoded["iat"]).to eq(3600)
            true
          end)
      end
    end

    context "with mobile client identifier" do
      let(:mobile_client_id) { "com.example.mobileapp" }

      before do
        StandardId.config.apple_mobile_client_id = mobile_client_id
      end

      after do
        StandardId.config.apple_mobile_client_id = nil
      end

      it "uses provided client_id for exchange" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, aud: mobile_client_id)
        stub_token_exchange_request(code: code, id_token: id_token, client_id: mobile_client_id)
        stub_jwks_request

        result = described_class.exchange_code_for_user_info(
          code: code,
          redirect_uri: redirect_uri,
          client_id: mobile_client_id
        )

        expect(result.dig(:user_info, :sub)).to eq(user_sub)
      end
    end

    context "when token exchange fails" do
      it "raises an error with the failure reason" do
        stub_request(:post, "https://appleid.apple.com/auth/token")
          .to_return(status: 400, body: { error: "invalid_grant", error_description: "code is invalid" }.to_json)

        expect do
          described_class.exchange_code_for_user_info(code: code, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError, /Failed to exchange Apple authorization code: invalid_grant/)
      end

      it "falls back to the HTTP status when the body names no error" do
        stub_request(:post, "https://appleid.apple.com/auth/token").to_return(status: 502, body: "<html>")

        expect do
          described_class.exchange_code_for_user_info(code: code, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError, /Failed to exchange Apple authorization code: HTTP 502/)
      end
    end

    context "when id_token is missing from response" do
      it "raises an error" do
        stub_request(:post, "https://appleid.apple.com/auth/token")
          .to_return(status: 200, body: { access_token: "token123" }.to_json)

        expect do
          described_class.exchange_code_for_user_info(code: code, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError, /Apple token response is missing id_token/)
      end
    end

    context "when credentials are incomplete" do
      before { StandardId.config.apple_private_key = nil }

      it "raises an error" do
        expect do
          described_class.exchange_code_for_user_info(code: code, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError, /Apple OAuth credentials are incomplete: apple_private_key not set/)
      end

      it "does not call Apple" do
        expect do
          described_class.exchange_code_for_user_info(code: code, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::InvalidRequestError)
        expect(WebMock).not_to have_requested(:post, "https://appleid.apple.com/auth/token")
      end
    end

    context "when a non-OAuth error is raised" do
      it "wraps it in StandardId::OAuthError, keeping the cause" do
        allow(StandardId::HttpClient).to receive(:post_form).and_raise(Errno::ECONNRESET)

        expect do
          described_class.exchange_code_for_user_info(code: code, redirect_uri: redirect_uri)
        end.to raise_error(StandardId::OAuthError) { |error| expect(error.cause).to be_a(Errno::ECONNRESET) }
      end
    end
  end

  describe ".verify_id_token" do
    let(:user_sub) { "001234.abcd1234abcd1234abcd1234abcd1234.1234" }
    let(:user_email) { "user@example.com" }

    context "with valid id_token" do
      it "verifies signature and returns user info" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, email_verified: true)
        stub_jwks_request

        result = described_class.verify_id_token(id_token: id_token)

        expect(result["sub"]).to eq(user_sub)
        expect(result["email"]).to eq(user_email)
        expect(result["email_verified"]).to eq("true")
      end
    end

    context "with expired id_token" do
      it "raises an error" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, exp: Time.now.to_i - 3600)
        stub_jwks_request

        expect do
          described_class.verify_id_token(id_token: id_token)
        end.to raise_error(StandardId::InvalidRequestError, /Invalid Apple ID token/)
      end
    end

    context "with wrong audience" do
      it "raises an error" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, aud: "wrong.client.id")
        stub_jwks_request

        expect do
          described_class.verify_id_token(id_token: id_token)
        end.to raise_error(StandardId::InvalidRequestError, /Invalid Apple ID token audience/)
      end
    end

    context "with mobile client ID" do
      let(:mobile_client_id) { "com.example.mobileapp" }

      before do
        StandardId.config.apple_mobile_client_id = mobile_client_id
      end

      after do
        StandardId.config.apple_mobile_client_id = nil
      end

      it "verifies id_token with mobile client_id successfully" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email, aud: mobile_client_id)
        stub_jwks_request

        result = described_class.verify_id_token(id_token: id_token, client_id: mobile_client_id)

        expect(result["sub"]).to eq(user_sub)
        expect(result["email"]).to eq(user_email)
      end
    end

    context "with invalid signature" do
      it "raises an error" do
        wrong_key = OpenSSL::PKey::RSA.new(2048)
        wrong_kid = "WRONGKID"
        payload = {
          iss: "https://appleid.apple.com",
          aud: apple_client_id,
          sub: user_sub,
          email: user_email,
          iat: Time.now.to_i,
          exp: Time.now.to_i + 3600
        }
        id_token = JWT.encode(payload, wrong_key, "RS256", kid: wrong_kid)

        stub_request(:get, "https://appleid.apple.com/auth/keys")
          .to_return(status: 200, body: { keys: [] }.to_json)

        expect do
          described_class.verify_id_token(id_token: id_token)
        end.to raise_error(StandardId::InvalidRequestError, /signing key not found in Apple's JWKS/)
      end
    end

    context "when JWKS fetch fails" do
      it "raises an error" do
        id_token = generate_test_id_token(sub: user_sub, email: user_email)
        stub_request(:get, "https://appleid.apple.com/auth/keys")
          .to_return(status: 500)

        expect do
          described_class.verify_id_token(id_token: id_token)
        end.to raise_error(StandardId::OAuthError, /Failed to fetch Apple JWKS: HTTP 500/)
      end
    end
  end

  describe "nonce verification" do
    let(:user_sub) { "001234.nonce" }
    let(:user_email) { "user@example.com" }
    let(:expected_nonce) { "server-issued-nonce-4f1c" }

    before { stub_jwks_request }

    it "accepts a matching nonce" do
      id_token = generate_test_id_token(sub: user_sub, email: user_email, nonce: expected_nonce)

      expect(described_class.verify_id_token(id_token: id_token, nonce: expected_nonce)["sub"]).to eq(user_sub)
    end

    it "rejects a mismatched nonce without echoing either value" do
      id_token = generate_test_id_token(sub: user_sub, email: user_email, nonce: "attacker-nonce-9z")

      expect do
        described_class.verify_id_token(id_token: id_token, nonce: expected_nonce)
      end.to raise_error(StandardId::InvalidRequestError) { |error|
        expect(error.message).to eq("ID token nonce mismatch")
        expect(error.message).not_to include(expected_nonce)
        expect(error.message).not_to include("attacker-nonce-9z")
      }
    end

    it "rejects a token with no nonce when one was issued" do
      id_token = generate_test_id_token(sub: user_sub, email: user_email)

      expect do
        described_class.get_user_info(id_token: id_token, nonce: expected_nonce)
      end.to raise_error(StandardId::InvalidRequestError, "ID token nonce mismatch")
    end

    it "skips the check when no nonce was issued (native flow)" do
      id_token = generate_test_id_token(sub: user_sub, email: user_email, nonce: "client-side-nonce")

      expect(described_class.verify_id_token(id_token: id_token)["sub"]).to eq(user_sub)
    end
  end

  describe "JWKS fetching" do
    let(:user_email) { "user@example.com" }

    it "goes through StandardId::HttpClient's address guard" do
      stub_jwks_request
      allow(StandardId::HttpClient).to receive(:validate_url!).and_call_original

      described_class.verify_id_token(id_token: generate_test_id_token(sub: "a", email: user_email))

      expect(StandardId::HttpClient).to have_received(:validate_url!).with(described_class::JWKS_URI)
    end

    it "caches the key set between verifications" do
      stub = stub_jwks_request

      2.times { described_class.verify_id_token(id_token: generate_test_id_token(sub: "a", email: user_email)) }

      expect(stub).to have_been_requested.once
    end

    it "refetches after the TTL" do
      stub = stub_jwks_request
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now)
      described_class.verify_id_token(id_token: generate_test_id_token(sub: "a", email: user_email))

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
        .and_return(now + described_class::JWKS_CACHE_TTL + 1)
      described_class.verify_id_token(id_token: generate_test_id_token(sub: "a", email: user_email))

      expect(stub).to have_been_requested.twice
    end

    context "when Apple rotates its keys" do
      let(:rotated_key) { OpenSSL::PKey::RSA.new(2048) }
      let(:rotated_token) do
        JWT.encode(
          { iss: "https://appleid.apple.com", aud: apple_client_id, sub: "a", iat: Time.now.to_i, exp: Time.now.to_i + 3600 },
          rotated_key, "RS256", kid: "ROTATED"
        )
      end
      let(:now) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      before do
        stub_request(:get, described_class::JWKS_URI).to_return(
          { status: 200, body: { keys: [jwk_hash(test_rsa_key, test_kid)] }.to_json },
          { status: 200, body: { keys: [jwk_hash(test_rsa_key, test_kid), jwk_hash(rotated_key, "ROTATED")] }.to_json }
        )
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now)
        described_class.verify_id_token(id_token: generate_test_id_token(sub: "a", email: user_email))
      end

      it "refetches once on an unknown kid" do
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(now + described_class::JWKS_MIN_REFRESH_INTERVAL)

        expect(described_class.verify_id_token(id_token: rotated_token)["sub"]).to eq("a")
        expect(WebMock).to have_requested(:get, described_class::JWKS_URI).twice
      end

      it "does not refetch for an unknown kid within the refresh floor" do
        expect do
          described_class.verify_id_token(id_token: rotated_token)
        end.to raise_error(StandardId::InvalidRequestError, /signing key not found/)
        expect(WebMock).to have_requested(:get, described_class::JWKS_URI).once
      end
    end

    it "rejects a token whose header has no kid" do
      token = JWT.encode({ iss: "https://appleid.apple.com", aud: apple_client_id, sub: "a" }, test_rsa_key, "RS256")

      expect do
        described_class.verify_id_token(id_token: token)
      end.to raise_error(StandardId::InvalidRequestError, "Invalid Apple ID token: header has no kid")
    end

    it "wraps network failures" do
      stub_request(:get, described_class::JWKS_URI).to_timeout

      expect do
        described_class.verify_id_token(id_token: generate_test_id_token(sub: "a", email: user_email))
      end.to raise_error(StandardId::OAuthError, /\AFailed to fetch Apple JWKS: /)
    end
  end

  describe ".skip_csrf?" do
    it "is true, because Apple posts the web callback (form_post)" do
      expect(described_class.skip_csrf?).to be(true)
    end
  end

  describe ".supports_mobile_callback?" do
    it "is true" do
      expect(described_class.supports_mobile_callback?).to be(true)
    end
  end

  describe ".flow_for" do
    it "is :web only for flow=web" do
      expect(described_class.flow_for({ flow: "web" })).to eq(:web)
      expect(described_class.flow_for({ flow: "WEB" })).to eq(:web)
    end

    it "is :mobile otherwise" do
      expect(described_class.flow_for({})).to eq(:mobile)
      expect(described_class.flow_for({ flow: "ios" })).to eq(:mobile)
    end
  end

  describe ".resolve_params" do
    before { StandardId.config.apple_mobile_client_id = "com.example.mobileapp" }
    after { StandardId.config.apple_mobile_client_id = nil }

    it "uses the Services ID for the web flow" do
      expect(described_class.resolve_params({ code: "c" }, context: { flow: :web })).to eq(code: "c", client_id: apple_client_id)
    end

    it "defaults to the web flow" do
      expect(described_class.resolve_params({ code: "c" })[:client_id]).to eq(apple_client_id)
    end

    it "uses the bundle ID for the mobile flow" do
      expect(described_class.resolve_params({ id_token: "t" }, context: { flow: :mobile })[:client_id]).to eq("com.example.mobileapp")
    end
  end

  describe "configuration" do
    it "requires the three signing credentials" do
      expect(described_class.required_config_fields).to contain_exactly(:apple_private_key, :apple_key_id, :apple_team_id)
    end

    it "is enabled by apple_client_id" do
      expect(described_class.enabling_config_field).to eq(:apple_client_id)
      expect(described_class).to be_enabled
      StandardId.config.apple_client_id = nil
      expect(described_class).not_to be_enabled
    end

    it "reports missing signing credentials by name while enabled" do
      StandardId.config.apple_key_id = nil
      StandardId.config.apple_team_id = ""

      expect(described_class.configuration_errors).to contain_exactly(
        "apple_key_id is required when apple_client_id is set",
        "apple_team_id is required when apple_client_id is set"
      )
      expect(described_class).not_to be_configured
    end

    it "reports nothing when disabled, even with credentials missing" do
      StandardId.config.apple_client_id = nil
      StandardId.config.apple_private_key = nil

      expect(described_class.configuration_errors).to be_empty
    end

    describe "ENV fallback" do
      around do |example|
        saved = ENV.to_h.slice("APPLE_PRIVATE_KEY", "APPLE_PRIVATE_KEY_PEM", "APPLE_TEAM_ID")
        example.run
      ensure
        %w[APPLE_PRIVATE_KEY APPLE_PRIVATE_KEY_PEM APPLE_TEAM_ID].each { |name| ENV[name] = saved[name] }
      end

      before do
        StandardId.config.social.delete(:apple_private_key)
        StandardId.config.social.delete(:apple_team_id)
        described_class.instance_variable_set(:@legacy_private_key_warned, nil)
      end

      it "reads the canonical upper-cased names" do
        ENV["APPLE_TEAM_ID"] = "ENVTEAM"
        ENV["APPLE_PRIVATE_KEY"] = "canonical-pem"

        expect(StandardId.config.apple_team_id).to eq("ENVTEAM")
        expect(StandardId.config.apple_private_key).to eq("canonical-pem")
      end

      it "falls back to the deprecated APPLE_PRIVATE_KEY_PEM, warning once" do
        ENV.delete("APPLE_PRIVATE_KEY")
        ENV["APPLE_PRIVATE_KEY_PEM"] = "legacy-pem"
        allow(StandardId.deprecator).to receive(:warn)

        2.times { expect(StandardId.config.apple_private_key).to eq("legacy-pem") }
        expect(StandardId.deprecator).to have_received(:warn).with(/APPLE_PRIVATE_KEY_PEM is deprecated/).once
      end

      it "prefers APPLE_PRIVATE_KEY over the deprecated name" do
        ENV["APPLE_PRIVATE_KEY"] = "canonical-pem"
        ENV["APPLE_PRIVATE_KEY_PEM"] = "legacy-pem"

        expect(StandardId.config.apple_private_key).to eq("canonical-pem")
      end

      it "loses to explicit configuration" do
        ENV["APPLE_PRIVATE_KEY"] = "canonical-pem"
        StandardId.config.apple_private_key = "explicit-pem"

        expect(StandardId.config.apple_private_key).to eq("explicit-pem")
      end
    end
  end

  def jwk_hash(key, kid)
    JWT::JWK.new(key).export.merge(kid: kid, alg: "RS256", use: "sig")
  end

  def generate_test_id_token(sub:, email:, email_verified: nil, is_private_email: nil, aud: nil, exp: nil, nonce: nil)
    payload = {
      iss: "https://appleid.apple.com",
      aud: aud || apple_client_id,
      sub: sub,
      email: email,
      iat: Time.now.to_i,
      exp: exp || (Time.now.to_i + 3600)
    }

    payload[:email_verified] = email_verified.to_s if email_verified
    payload[:is_private_email] = is_private_email.to_s if is_private_email
    payload[:nonce] = nonce if nonce

    JWT.encode(payload, test_rsa_key, "RS256", kid: test_kid)
  end

  def stub_jwks_request
    stub_request(:get, "https://appleid.apple.com/auth/keys")
      .to_return(status: 200, body: { keys: [jwk_hash(test_rsa_key, test_kid)] }.to_json)
  end

  def stub_token_exchange_request(code:, id_token:, client_id: apple_client_id)
    stub_request(:post, "https://appleid.apple.com/auth/token")
      .with do |req|
        body = URI.decode_www_form(req.body).to_h
        body["code"] == code &&
          body["grant_type"] == "authorization_code" &&
          body["client_id"] == client_id
      end
      .to_return(
        status: 200,
        body: {
          access_token: "test_access_token",
          token_type: "Bearer",
          expires_in: 3600,
          refresh_token: "test_refresh_token",
          id_token: id_token
        }.to_json
      )
  end
end
