# LLM provider configuration. All accessors are lazy (evaluated only when an
# Actor actually calls them) so boot/migrate/test runs never crash just because
# an API key isn't set yet (see docs/architecture_plan.md §16).
#
# Modular by design (per user request): switching providers is a one-line env
# var change (LLM_PROVIDER=openai|claude|gemini) plus the matching API key —
# no code changes. See app/services/llm/provider.rb for the abstraction this
# config feeds into.
TEST_SCOPE_PROMPT_VERSION = ENV.fetch("TEST_SCOPE_PROMPT_VERSION", "v1").freeze

module LlmConfig
  DEFAULT_MODELS = {
    "openai" => "gpt-4.1",
    "claude" => "claude-sonnet-4-5",
    "gemini" => "gemini-2.5-flash",
  }.freeze

  API_KEY_ENV_VARS = {
    "openai" => "OPENAI_API_KEY",
    "claude" => "ANTHROPIC_API_KEY",
    "gemini" => "GEMINI_API_KEY",
  }.freeze

  def self.provider
    ENV.fetch("LLM_PROVIDER", "gemini")
  end

  def self.model
    ENV.fetch("LLM_MODEL", DEFAULT_MODELS.fetch(provider) { raise "Unsupported LLM_PROVIDER: #{provider}" })
  end

  def self.api_key
    env_var = API_KEY_ENV_VARS.fetch(provider) { raise "Unsupported LLM_PROVIDER: #{provider}" }
    ENV.fetch(env_var)
  end
end
