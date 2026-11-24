# frozen_string_literal: true

require "spec_helper"

# standard_health is not in this bundle, so the hook is exercised the way
# standard_health fires it: run_load_hooks(:standard_health, registry). The
# fake records calls through the only methods the real registry exposes (so
# the hook calling anything else fails with NoMethodError) and keeps each
# entry's options, `if:` predicate included, for the examples to evaluate.
RSpec.describe "standard_id-apple's standard_health load hook" do
  let(:env_spec_dsl) do
    Class.new do
      attr_reader :entries

      def initialize
        @entries = []
      end

      def required(name, **options) = @entries << [:required, name, options]
      def recommended(name, **options) = @entries << [:recommended, name, options]
      def forbidden(name, **options) = @entries << [:forbidden, name, options]
    end
  end

  let(:registry) do
    dsl_class = env_spec_dsl
    Class.new do
      attr_reader :env_vars

      define_method(:initialize) do
        @env_vars = {}
        @dsl_class = dsl_class
      end

      # standard_id's own hook contributes a check; accept it.
      def contribute_check(*, **); end

      def contribute_env_vars(contributor, &block)
        @env_vars[contributor] = @dsl_class.new.tap { |dsl| dsl.instance_eval(&block) }.entries
      end
    end.new
  end

  let(:social) { StandardId.config.social }
  let(:entries) { registry.env_vars.fetch("standard_id-apple") }
  let(:signing_triple) { %i[APPLE_PRIVATE_KEY APPLE_KEY_ID APPLE_TEAM_ID] }

  def entry(name) = entries.find { |_, entry_name, _| entry_name == name }

  def applies?(name)
    predicate = entry(name)[2][:if]
    predicate.nil? || predicate.call
  end

  context "without standard_health" do
    it "registers the hook without loading or needing standard_health, and runs nothing" do
      expect(defined?(StandardHealth)).to be_nil
      expect(ActiveSupport.instance_variable_get(:@load_hooks)[:standard_health]).not_to be_empty
      expect(ActiveSupport.instance_variable_get(:@loaded)[:standard_health]).to be_blank
      expect(Gem.loaded_specs["standard_id-apple"].runtime_dependencies.map(&:name)).not_to include("standard_health")
    end
  end

  context "when standard_health fires its load hooks" do
    before { ActiveSupport.run_load_hooks(:standard_health, registry) }

    # run_load_hooks remembers its base so later on_load calls fire on it; drop
    # the fake so it cannot reach another example. Forget any field an example
    # assigned, so reads fall back to the schema default again.
    after do
      ActiveSupport.instance_variable_get(:@loaded)[:standard_health]&.delete(registry)
      StandardId::Providers::Apple.config_schema.each_key { |field| social.delete(field) }
    end

    it "declares every env var the plugin reads, under its own contributor" do
      expect(entries.map { |level, name, _| [level, name] }).to eq(
        [
          %i[recommended APPLE_CLIENT_ID], %i[recommended APPLE_MOBILE_CLIENT_ID], %i[recommended APPLE_REDIRECT_URI],
          %i[required APPLE_PRIVATE_KEY], %i[required APPLE_KEY_ID], %i[required APPLE_TEAM_ID]
        ]
      )
    end

    it "covers every config field that falls back to ENV" do
      env_names = StandardId::Providers::Apple.config_schema.filter_map do |field, options|
        StandardId::ProviderRegistry.env_var_for(field, options)
      end

      expect(entries.map { |_, name, _| name.to_s }).to match_array(env_names)
    end

    it "requires exactly the fields StandardId's boot check requires" do
      required = entries.filter_map { |level, name, _| name.to_s.downcase.to_sym if level == :required }

      expect(required).to match_array(StandardId::Providers::Apple.required_config_fields)
    end

    it "describes every env var" do
      expect(entries.map { |_, _, options| options[:description] }).to all(be_present)
    end

    it "restricts nothing by environment" do
      expect(entries.map { |_, _, options| options[:in] }).to all(be_nil)
    end

    it "leaves the client IDs unconditional and advisory" do
      expect(entry(:APPLE_CLIENT_ID)[2].keys).to eq([:description])
      expect(entry(:APPLE_MOBILE_CLIENT_ID)[2].keys).to eq([:description])
    end

    describe "the signing triple and APPLE_REDIRECT_URI" do
      it "do not apply while the provider is off" do
        expect(StandardId::Providers::Apple).not_to be_enabled
        expect(signing_triple + [:APPLE_REDIRECT_URI]).to all(satisfy { |name| !applies?(name) })
      end

      it "do not apply on the mobile client ID alone, which needs no signing key" do
        social.apple_mobile_client_id = "com.example.app"

        expect(signing_triple + [:APPLE_REDIRECT_URI]).to all(satisfy { |name| !applies?(name) })
      end

      it "apply once the provider is on and the fields are left to ENV" do
        social.apple_client_id = "com.example.web"

        expect(signing_triple + [:APPLE_REDIRECT_URI]).to all(satisfy { |name| applies?(name) })
      end

      it "drop each field the app assigns itself" do
        social.apple_client_id = "com.example.web"
        social.apple_key_id = "KEY123"

        expect(applies?(:APPLE_KEY_ID)).to be(false)
        expect(applies?(:APPLE_PRIVATE_KEY)).to be(true)
        expect(applies?(:APPLE_TEAM_ID)).to be(true)
      end

      it "drop APPLE_PRIVATE_KEY while the deprecated APPLE_PRIVATE_KEY_PEM supplies it" do
        social.apple_client_id = "com.example.web"
        saved = ENV.fetch("APPLE_PRIVATE_KEY_PEM", nil)
        ENV["APPLE_PRIVATE_KEY_PEM"] = "legacy-pem"

        expect(applies?(:APPLE_PRIVATE_KEY)).to be(false)
        expect(applies?(:APPLE_KEY_ID)).to be(true)
      ensure
        ENV["APPLE_PRIVATE_KEY_PEM"] = saved
      end
    end
  end
end
