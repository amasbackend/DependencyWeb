require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RelateDoc
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.active_support.cache_format_version = 7.0
    config.autoload_paths << Rails.root.join("lib")
    config.cache_classes = false
    config.eager_load = false
    config.reload_classes_only_on_change = true
  end
end
