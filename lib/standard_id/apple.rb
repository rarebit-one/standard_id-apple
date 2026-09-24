require "active_support/core_ext/numeric/time"
require "active_support/core_ext/hash/indifferent_access"
require "standard_id"
require "standard_id/apple/version"
require "standard_id/apple/providers/apple"

# Registers the provider from a Railtie's after_initialize (a no-op outside
# Rails). Its config fields are declared earlier, before config/initializers,
# by standard_id's own engine initializer.
StandardId::Providers.plugin_railtie(:apple, "StandardId::Providers::Apple")
