module Llm
  # Abstract interface every concrete provider implements. Selecting a
  # provider is a config change (LLM_PROVIDER + its API key env var), never a
  # code change in any caller — this is the whole point of the abstraction
  # (per user request for GPT/Claude/Gemini to be swappable via paid key).
  class Provider
    class Error < StandardError; end

    # Internal-only signal for #with_retry — never escapes it.
    class RetryableResponse < StandardError; end

    # Up to two retries (3 attempts total) — generous enough to ride out a
    # transient blip without turning a real outage into a long hang; see
    # #with_retry for exactly what's retryable.
    MAX_ATTEMPTS = 3

    # Seconds to wait before retry N (1-indexed) — a 429 needs an actual
    # pause to clear (confirmed live: the same key went from 429 to success
    # a few seconds later with no other change), unlike a 5xx/network blip
    # where an instant retry is often enough.
    BACKOFF_SECONDS = 2

    def self.current
      case LlmConfig.provider
      when "openai" then Llm::OpenAiProvider.new
      when "claude" then Llm::ClaudeProvider.new
      when "claude_cli" then Llm::ClaudeCliProvider.new
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
    # temperature: optional Float, passed through to the provider when given;
    #   omitted from the request entirely when nil, so not passing one
    #   leaves each provider's own default behavior unchanged.
    # Returns an Llm::Response.
    def generate(prompt:, system: nil, json: false, temperature: nil)
      raise NotImplementedError
    end

    private

    # Retries a transient failure — a network-level error, a 5xx response, or
    # a 429 (rate limit) — up to MAX_ATTEMPTS total attempts, pausing
    # BACKOFF_SECONDS * attempt between tries. Any other 4xx (bad request,
    # bad API key) is never retried since retrying won't fix it; the
    # caller's existing `unless response.success?` check still raises
    # Provider::Error for those, unchanged. This never wraps response
    # *parsing* or schema validation — a well-formed-but-invalid LLM answer
    # is Llm::AnalyzeTestScope's concern, entirely outside this retry, so a
    # bad answer still hard-fails once rather than being silently retried
    # into a different non-deterministic one.
    def with_retry
      attempts = 0
      begin
        attempts += 1
        response = yield
        if !response.success? && retryable_status?(response.status) && attempts < MAX_ATTEMPTS
          sleep(BACKOFF_SECONDS * attempts)
          raise RetryableResponse
        end

        response
      rescue RetryableResponse
        retry
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed
        raise if attempts >= MAX_ATTEMPTS
        sleep(BACKOFF_SECONDS * attempts)
        retry
      end
    end

    def retryable_status?(status)
      status >= 500 || status == 429
    end
  end
end
