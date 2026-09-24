# frozen_string_literal: true

require "spec_helper"
require "standard_id/testing/provider_examples"

RSpec.describe "standard_id-apple registration" do
  it_behaves_like "a registered StandardId provider", :apple

  it "registers StandardId::Providers::Apple" do
    expect(StandardId::ProviderRegistry.get(:apple)).to eq(StandardId::Providers::Apple)
  end

  it "declares every field on the social scope" do
    expect(:apple).to be_a_registered_standard_id_provider.with_config_fields(
      :apple_client_id, :apple_mobile_client_id, :apple_private_key, :apple_key_id, :apple_team_id
    )
  end

  it "is registered by the Railtie standard_id's plugin_railtie defines" do
    expect(StandardId::Providers::Railties::Apple).to be < Rails::Railtie
  end
end
