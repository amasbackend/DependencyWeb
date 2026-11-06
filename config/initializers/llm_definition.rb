# LLM provider configuration. All accessors are lazy (evaluated only when an
# Actor actually calls them) so boot/migrate/test runs never crash just because
# an API key isn't set yet (see docs/architecture_plan.md §16).
#
# Modular by design (per user request): switching providers is a one-line env
# var change (LLM_PROVIDER=openai|claude|gemini) plus the matching API key —
# no code changes. See app/services/llm/provider.rb for the abstraction this
# config feeds into. LLM_PROVIDER=claude_cli needs no key: it goes through the
# logged-in `claude` CLI (see Llm::ClaudeCliProvider).
TEST_SCOPE_PROMPT_VERSION = ENV.fetch("TEST_SCOPE_PROMPT_VERSION", "v2").freeze

module LlmConfig
  DEFAULT_MODELS = {
    "openai" => "gpt-4.1",
    "claude" => "claude-sonnet-4-5",
    # gemini-2.5-flash was retired for new users (confirmed via a real API
    # call returning 404 "no longer available to new users" — see
    # docs/architecture_plan.md's note that no live key had ever been
    # exercised before now); Google's own error names this replacement.
    "gemini" => "gemini-3.6-flash",
    "claude_cli" => "claude-opus-5-5",
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

  def self.claude_cli_path
    ENV.fetch("CLAUDE_CLI_PATH", "claude")
  end

  # claude_cli only (low|medium|high|xhigh|max, passed as `claude --effort`);
  # unset leaves the CLI's own default, same opt-in rule as temperature.
  def self.effort
    ENV["LLM_EFFORT"].presence
  end

  # Unset by default (nil) — leaves every provider's own default temperature
  # unchanged unless an operator explicitly opts in. §63 recommends 0~0.2 for
  # this kind of analytical (not creative) task once a real key is live; not
  # defaulted here to avoid silently changing behavior no one asked for yet.
  def self.temperature
    ENV["LLM_TEMPERATURE"]&.to_f
  end
end
