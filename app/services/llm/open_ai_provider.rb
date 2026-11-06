require "faraday"

module Llm
  class OpenAiProvider < Provider
    API_URL = "https://api.openai.com/v1/chat/completions".freeze
    JSON_INSTRUCTION = "\n\nRespond with valid JSON only — no prose, no markdown code fences.".freeze

    def generate(prompt:, system: nil, json: false, temperature: nil)
      messages = []
      messages << { role: "system", content: system } if system.present?
      messages << { role: "user", content: json ? "#{prompt}#{JSON_INSTRUCTION}" : prompt }

      response = with_retry do
        connection.post do |req|
          req.body = { model: LlmConfig.model, messages: messages }
          req.body[:response_format] = { type: "json_object" } if json
          req.body[:temperature] = temperature if temperature
        end
      end

      raise Provider::Error, "OpenAI API error (#{response.status}): #{response.body}" unless response.success?

      body = response.body
      choice = body.fetch("choices").first.fetch("message").fetch("content")
      usage = body.fetch("usage", {})

      Llm::Response.new(
        content: choice,
        input_tokens: usage["prompt_tokens"],
        cached_input_tokens: usage.dig("prompt_tokens_details", "cached_tokens"),
        output_tokens: usage["completion_tokens"],
        provider: "openai",
        model: body["model"] || LlmConfig.model,
      )
    end

    private

    def connection
      Faraday.new(url: API_URL) do |f|
        f.request :json
        f.response :json
        f.headers["Authorization"] = "Bearer #{LlmConfig.api_key}"
      end
    end
  end
end
