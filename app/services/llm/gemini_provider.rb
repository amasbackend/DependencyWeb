require "faraday"

module Llm
  class GeminiProvider < Provider
    API_URL = "https://generativelanguage.googleapis.com/v1beta/models".freeze
    JSON_INSTRUCTION = "\n\nRespond with valid JSON only — no prose, no markdown code fences.".freeze

    def generate(prompt:, system: nil, json: false)
      response = connection.post("#{LlmConfig.model}:generateContent") do |req|
        req.params["key"] = LlmConfig.api_key
        req.body = { contents: [ { parts: [ { text: json ? "#{prompt}#{JSON_INSTRUCTION}" : prompt } ] } ] }
        req.body[:systemInstruction] = { parts: [ { text: system } ] } if system.present?
        req.body[:generationConfig] = { responseMimeType: "application/json" } if json
      end

      raise Provider::Error, "Gemini API error (#{response.status}): #{response.body}" unless response.success?

      body = response.body
      text = body.fetch("candidates").first.fetch("content").fetch("parts").first.fetch("text")
      usage = body.fetch("usageMetadata", {})

      Llm::Response.new(
        content: text,
        input_tokens: usage["promptTokenCount"],
        output_tokens: usage["candidatesTokenCount"],
        provider: "gemini",
        model: LlmConfig.model,
      )
    end

    private

    def connection
      Faraday.new(url: API_URL) do |f|
        f.request :json
        f.response :json
      end
    end
  end
end
