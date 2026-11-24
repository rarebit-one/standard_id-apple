# frozen_string_literal: true

require "spec_helper"
require "openssl"

# When the host's config.network_wrapper refuses a request itself (an open
# circuit), standard_id releases with StandardId::NetworkWrapper raise
# StandardId::ProviderUnavailableError instead of the wrapper's own error. The
# token helpers turn it into TokenRequestError like a transport failure; the
# sign-in flows let it through, since it is an OAuthError. Older releases have
# no such error, and the wrapper's error reaches the caller as before.
RSpec.describe StandardId::Providers::Apple, "network_wrapper refusals" do
  let(:apple_client_id) { "com.example.app" }
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:real_client) { StandardId::HttpClient }

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
  end

  after do
    StandardId.config.apple_client_id = nil
    StandardId.config.apple_team_id = nil
    StandardId.config.apple_key_id = nil
    StandardId.config.apple_private_key = nil
  end

  # An HttpClient stand-in whose calls listed in `refuse` raise `error` without
  # making the request (what a refusing wrapper does); the rest go to the real
  # client. It takes no provider: keyword, so it works with every release.
  def client_refusing(refuse, error)
    real = real_client
    Class.new do
      const_set(:SsrfError, real::SsrfError)

      define_singleton_method(:post_form) do |endpoint, params = nil|
        raise error.call if refuse.include?(:post_form)

        real.post_form(endpoint, params)
      end

      define_singleton_method(:validate_url!) { |url| real.send(:validate_url!, url) }
      define_singleton_method(:start_connection) do |uri, resolved_ip: nil, &block|
        raise error.call if refuse.include?(:start_connection)

        real.send(:start_connection, uri, resolved_ip: resolved_ip, &block)
      end
      private_class_method :validate_url!, :start_connection
    end
  end

  context "with a standard_id that raises ProviderUnavailableError" do
    before do
      unless defined?(StandardId::ProviderUnavailableError)
        stub_const("StandardId::ProviderUnavailableError", Class.new(StandardId::OAuthError) {
          define_method(:initialize) { |message = nil, provider: nil| super(message || "#{provider} is temporarily unavailable") }
        })
      end
    end

    let(:refusal) { -> { StandardId::ProviderUnavailableError.new(provider: :apple) } }

    it "turns a refused revocation into a retryable TokenRequestError, keeping the refusal as cause" do
      stub_const("StandardId::HttpClient", client_refusing([:post_form], refusal))

      expect {
        described_class.revoke(token: "r", token_type_hint: :refresh_token)
      }.to raise_error(StandardId::Apple::TokenRequestError) { |error|
        expect(error.message).to eq("Failed to revoke Apple token: StandardId::ProviderUnavailableError")
        expect(error.http_status_code).to be_nil
        expect(error).to be_retryable
        expect(error.cause).to be_a(StandardId::ProviderUnavailableError)
      }
      expect(WebMock).not_to have_requested(:post, "https://appleid.apple.com/auth/revoke")
    end

    it "turns a refused native code exchange into a retryable TokenRequestError" do
      stub_const("StandardId::HttpClient", client_refusing([:post_form], refusal))

      expect { described_class.exchange_authorization_code("code-2") }
        .to raise_error(StandardId::Apple::TokenRequestError, "Failed to exchange Apple authorization code: StandardId::ProviderUnavailableError") { |error|
          expect(error).to be_retryable
        }
    end

    it "reports a refused JWKS fetch after the code exchange as an outage, not an invalid id_token" do
      stub_const("StandardId::HttpClient", client_refusing([:start_connection], refusal))

      expect { described_class.exchange_authorization_code("code-2") }
        .to raise_error(StandardId::Apple::TokenRequestError) { |error|
          expect(error.message).to eq("Apple id_token from the token response could not be verified: StandardId::ProviderUnavailableError")
          expect(error.reason).to be_nil
          expect(error).to be_retryable
        }
    end

    it "lets the refusal through the sign-in flow, so core renders it as temporarily unavailable" do
      stub_const("StandardId::HttpClient", client_refusing([:post_form], refusal))

      expect {
        described_class.exchange_code_for_user_info(code: "code-1", redirect_uri: "https://example.com/callback")
      }.to raise_error(StandardId::ProviderUnavailableError, /\Aapple is temporarily unavailable\z/i)
    end

    it "still turns a transport error into TokenRequestError" do
      stub_const("StandardId::HttpClient", client_refusing([:post_form], -> { Net::OpenTimeout.new }))

      expect { described_class.revoke(token: "r") }
        .to raise_error(StandardId::Apple::TokenRequestError, "Failed to revoke Apple token: Net::OpenTimeout")
    end
  end

  context "with a standard_id that has no ProviderUnavailableError" do
    before { hide_const("StandardId::ProviderUnavailableError") }

    it "lets the wrapper's own error through unchanged, as before" do
      circuit_open = Class.new(StandardError)
      stub_const("StandardId::HttpClient", client_refusing([:post_form], -> { circuit_open.new("open") }))

      expect { described_class.revoke(token: "r") }.to raise_error(circuit_open, "open")
    end
  end

  # Against the real HttpClient and the host's wrapper; needs a standard_id
  # with StandardId::NetworkWrapper (run with a path override until released).
  context "with the host's network_wrapper" do
    let(:circuit_open) { Class.new(StandardError) }

    before do
      skip "needs a standard_id with StandardId::NetworkWrapper" unless defined?(StandardId::NetworkWrapper)
    end

    after { StandardId.config.network_wrapper = nil if defined?(StandardId::NetworkWrapper) }

    context "when the wrapper refuses without calling the block (an open circuit)" do
      before do
        error = circuit_open
        StandardId.config.network_wrapper = ->(provider:, &_block) { raise error, "oauth_#{provider} is open" }
      end

      it "turns revocation and the native exchange into retryable TokenRequestErrors, making no request" do
        expect { described_class.revoke(token: "r") }.to raise_error(StandardId::Apple::TokenRequestError) { |error|
          expect(error).to be_retryable
          expect(error.cause).to be_a(StandardId::ProviderUnavailableError)
          expect(error.cause.cause).to be_a(circuit_open)
        }
        expect { described_class.exchange_authorization_code("code-2") }.to raise_error(StandardId::Apple::TokenRequestError)
        expect(WebMock).not_to have_requested(:post, %r{appleid\.apple\.com/auth/})
      end

      it "fails the sign-in with ProviderUnavailableError for :apple" do
        expect {
          described_class.exchange_code_for_user_info(code: "code-1", redirect_uri: "https://example.com/callback")
        }.to raise_error(StandardId::ProviderUnavailableError, "Apple is temporarily unavailable") { |error|
          expect(error.provider).to eq(:apple)
        }
      end
    end

    context "when the wrapper raises after the request went through (a failing tracer)" do
      let(:tracer_failed) { Class.new(StandardError) }

      before do
        error = tracer_failed
        StandardId.config.network_wrapper = lambda do |provider:, &block|
          block.call
          raise error, "span export failed"
        end
      end

      it "lets the wrapper's error through unchanged, not as a retryable TokenRequestError (the code is spent)" do
        expect { described_class.exchange_authorization_code("code-2") }.to raise_error(tracer_failed, "span export failed")
        expect(WebMock).to have_requested(:post, "https://appleid.apple.com/auth/token").once
      end
    end

    context "when the wrapper calls the block" do
      before { StandardId.config.network_wrapper = ->(provider:, &block) { block.call } }

      it "behaves exactly as without a wrapper" do
        web = described_class.exchange_code_for_user_info(code: "code-1", redirect_uri: "https://example.com/callback")

        expect(web[:user_info]["sub"]).to eq("001234.abc")
        expect(described_class.exchange_authorization_code("code-2")[:tokens][:refresh_token]).to eq("r")
        expect(described_class.revoke(token: "r")).to be(true)
      end

      it "still turns a transport error raised inside the wrapper into TokenRequestError" do
        stub_request(:post, "https://appleid.apple.com/auth/revoke").to_timeout

        expect { described_class.revoke(token: "r") }
          .to raise_error(StandardId::Apple::TokenRequestError, "Failed to revoke Apple token: Net::OpenTimeout")
      end
    end
  end
end
