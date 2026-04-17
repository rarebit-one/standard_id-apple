# frozen_string_literal: true

module StandardId
  module Apple
    class Railtie < ::Rails::Railtie
      config.after_initialize do
        StandardId::ProviderRegistry.register(:apple, StandardId::Providers::Apple)

        Rails.logger.debug("[StandardId::Apple] registered provider") if Rails.logger
      end
    end
  end
end
