require "faraday"

module Llm
  class ClaudeProvider < Provider
    API_URL = "https://api.anthropic.com/v1/messages".freeze
    ANTHROPIC_VERSION = "2023-06-01".freeze
    MAX_TOKENS = 8192
    JSON_INSTRUCTION = "\n\nRespond with valid JSON only — no prose, no markdown code fences.".freeze

    def generate(prompt:, system: nil, json: false)
      response = connection.post do |req|
        req.body = {
          model: LlmConfig.model,
          max_tokens: MAX_TOKENS,
          messages: [ { role: "user", content: json ? "#{prompt}#{JSON_INSTRUCTION}" : prompt } ],
        }
        req.body[:system] = system if system.present?
      end

      raise Provider::Error, "Claude API error (#{response.status}): #{response.body}" unless response.success?

      body = response.body
      text = body.fetch("content").first.fetch("text")
      usage = body.fetch("usage", {})

      Llm::Response.new(
        content: text,
        input_tokens: usage["input_tokens"],
        output_tokens: usage["output_tokens"],
        provider: "claude",
        model: body["model"] || LlmConfig.model,
      )
    end

    private

    def connection
      Faraday.new(url: API_URL) do |f|
        f.request :json
        f.response :json
        f.headers["x-api-key"] = LlmConfig.api_key
        f.headers["anthropic-version"] = ANTHROPIC_VERSION
      end
    end
  end
end
