module Llm
  # Abstract interface every concrete provider implements. Selecting a
  # provider is a config change (LLM_PROVIDER + its API key env var), never a
  # code change in any caller — this is the whole point of the abstraction
  # (per user request for GPT/Claude/Gemini to be swappable via paid key).
  class Provider
    class Error < StandardError; end

    def self.current
      case LlmConfig.provider
      when "openai" then Llm::OpenAiProvider.new
      when "claude" then Llm::ClaudeProvider.new
      when "gemini" then Llm::GeminiProvider.new
      else raise Error, "Unsupported LLM_PROVIDER: #{LlmConfig.provider}"
      end
    end

    # system: optional system-prompt string
    # prompt: the user-prompt string
    # json: when true, instructs the model to respond with JSON only (every
    #   provider gets the same textual instruction, rather than relying on
    #   vendor-specific structured-output APIs that differ enough to
    #   undermine the "same format regardless of provider" goal)
    # Returns an Llm::Response.
    def generate(prompt:, system: nil, json: false)
      raise NotImplementedError
    end
  end
end
