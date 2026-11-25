# frozen_string_literal: true

require "spec_helper"
require "openssl"

# standard_id releases after 0.60.0 take `provider:` on HttpClient (for the
# host's config.network_wrapper); older ones raise ArgumentError on it. The
# provider must pass it to the first and leave it out for the second. Each
# context swaps in an HttpClient stand-in with one signature, so both paths are
# covered whichever standard_id the bundle resolves.
RSpec.describe StandardId::Providers::Apple, "HttpClient provider: keyword" do
  let(:apple_client_id) { "com.example.app" }
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }

  before do
    described_class.reset_jwks_cache!
    StandardId.config.apple_client_id = apple_client_id
    StandardId.config.apple_team_id = "TEAM123456"
    StandardId.config.apple_key_id = "KEY123456"
    StandardId.config.apple_private_key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    allow(Resolv).to receive(:getaddresses).and_return(["17.32.194.1"])

    now = Time.now.to_i
    id_token = JWT.encode(
      { iss: "https://appleid.apple.com", aud: apple_client_id, sub: "001234.abc", email: "u@example.com", iat: now, exp: now + 600 },
      rsa_key, "RS256", { kid: "kid-1" }
    )
    stub_request(:post, "https://appleid.apple.com/auth/token")
      .to_return(status: 200, body: { access_token: "a", refresh_token: "r", id_token: id_token }.to_json)
    stub_request(:post, "https://appleid.apple.com/auth/revoke").to_return(status: 200, body: "")
    stub_request(:get, "https://appleid.apple.com/auth/keys")
      .to_return(status: 200, body: { keys: [JWT::JWK.new(rsa_key).export.merge(kid: "kid-1", alg: "RS256", use: "sig")] }.to_json)

    stub_const("StandardId::HttpClient", client)
  end

  after do
    StandardId.config.apple_client_id = nil
    StandardId.config.apple_team_id = nil
    StandardId.config.apple_key_id = nil
    StandardId.config.apple_private_key = nil
  end

  # Web code exchange (token + JWKS), the native code exchange (token,
  # through post_to_apple) and revocation.
  def exercise_every_call
    web = described_class.exchange_code_for_user_info(code: "code-1", redirect_uri: "https://example.com/callback")
    described_class.exchange_authorization_code("code-2")
    described_class.revoke(token: "r", token_type_hint: :refresh_token)
    web
  end

  # Stand-ins for HttpClient with one fixed signature each. They delegate to
  # the real class (captured before stub_const) rather than subclassing it, so
  # the real methods' internal calls never land on the stand-in.
  let(:real_client) { StandardId::HttpClient }

  context "with a standard_id whose HttpClient takes provider:" do
    let(:calls) { [] }
    let(:client) do
      real = real_client
      recorded = calls
      Class.new do
        const_set(:SsrfError, real::SsrfError)

        define_singleton_method(:post_form) do |endpoint, params = nil, provider: :standard_id, **form|
          recorded << [:post_form, provider]
          real.post_form(endpoint, (params || {}).merge(form))
        end

        define_singleton_method(:validate_url!) { |url| real.send(:validate_url!, url) }
        define_singleton_method(:start_connection) do |uri, resolved_ip: nil, provider: :standard_id, &block|
          recorded << [:start_connection, provider]
          real.send(:start_connection, uri, resolved_ip: resolved_ip, &block)
        end
        private_class_method :validate_url!, :start_connection
      end
    end

    it "names :apple on every request: both code exchanges, the JWKS and revocation" do
      exercise_every_call

      expect(calls).to eq([
        %i[post_form apple],
        %i[start_connection apple],
        %i[post_form apple],
        %i[post_form apple]
      ])
    end
  end

  context "with a standard_id whose HttpClient has no provider: keyword (0.60.0 and older)" do
    let(:client) do
      real = real_client
      Class.new do
        const_set(:SsrfError, real::SsrfError)

        define_singleton_method(:post_form) { |endpoint, params| real.post_form(endpoint, params) }
        define_singleton_method(:validate_url!) { |url| real.send(:validate_url!, url) }
        define_singleton_method(:start_connection) do |uri, resolved_ip: nil, &block|
          real.send(:start_connection, uri, resolved_ip: resolved_ip, &block)
        end
        private_class_method :validate_url!, :start_connection
      end
    end

    it "makes every request without passing provider:" do
      result = exercise_every_call

      expect(result[:user_info]["sub"]).to eq("001234.abc")
      expect(WebMock).to have_requested(:post, "https://appleid.apple.com/auth/token").twice
      expect(WebMock).to have_requested(:get, "https://appleid.apple.com/auth/keys")
      expect(WebMock).to have_requested(:post, "https://appleid.apple.com/auth/revoke")
    end
  end
end
