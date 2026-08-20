require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DependencyWeb2
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Reports read as UTC+8 timestamps throughout (see spec_sample.md's own
    # "2026-07-31 16:38:49（UTC+8）" convention) — matches the zh-TW operator
    # audience this whole app targets. Storage stays UTC either way; this
    # only affects display formatting (e.g. Reports::RenderMarkdown, Phase 13).
    config.time_zone = "Asia/Taipei"
    # config.eager_load_paths << Rails.root.join("extras")

    config.i18n.default_locale = :"zh-TW"
    config.i18n.available_locales = [:"zh-TW"]
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}")]

    # Solid Queue's own tables live in a separate local SQLite database, not the
    # primary MySQL 5.7 one — MySQL 5.7 doesn't support SKIP LOCKED, which Solid
    # Queue's dispatcher requires (MySQL 8+). See docs/architecture_plan.md §14.
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue } }
  end
end
