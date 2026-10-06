# frozen_string_literal: true

module StandardId
  module Apple
    # Raised by the token helpers (`exchange_authorization_code`, `revoke`)
    # when Apple rejects a request or cannot be reached.
    #
    # Subclasses StandardId::InvalidRequestError so existing `rescue
    # StandardId::InvalidRequestError` / `rescue StandardId::OAuthError`
    # handling keeps working. The message names Apple's `error` value (or the
    # HTTP status, or the network failure class) — never a token, code or
    # client secret.
    class TokenRequestError < StandardId::InvalidRequestError
      # @return [String, nil] Apple's `error` value, e.g. "invalid_grant"
      #   (see Apple's ErrorResponse: invalid_request, invalid_client,
      #   invalid_grant, unauthorized_client, unsupported_grant_type,
      #   invalid_scope)
      attr_reader :reason

      # @return [Integer, nil] Apple's HTTP status; nil when no response was
      #   received (timeout, connection failure)
      attr_reader :http_status_code

      def initialize(message = nil, reason: nil, http_status_code: nil)
        super(message)
        @reason = reason
        @http_status_code = http_status_code
      end

      # True when retrying the same request may succeed: no response at all
      # (timeout, connection error), throttling or an Apple-side 5xx.
      def retryable?
        http_status_code.nil? || http_status_code == 429 || http_status_code >= 500
      end

      # The authorization code (or token) is invalid, expired or already
      # used. Authorization codes are single-use and valid for five minutes,
      # so the remedy is a fresh code from the client, not a retry.
      def invalid_grant?
        reason == "invalid_grant"
      end
    end

    # The Apple signing credentials (team id, key id, private key) or the
    # client id needed to sign a client_secret are not configured. A server
    # misconfiguration, not a client error.
    class CredentialsMissingError < StandardId::InvalidRequestError; end
  end
end
