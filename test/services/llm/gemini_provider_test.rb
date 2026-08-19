require "test_helper"

class Llm::GeminiProviderTest < ActiveSupport::TestCase
  test "parses content and usage from a real-shaped Gemini response" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1beta/models/gemini-2.5-flash:generateContent") do
        [
          200,
          { "Content-Type" => "application/json" },
          {
            candidates: [ { content: { parts: [ { text: '{"summary":"ok"}' } ] } } ],
            usageMetadata: { promptTokenCount: 15, candidatesTokenCount: 6 },
          }.to_json,
        ]
      end
    end
    fake_connection = Faraday.new(url: Llm::GeminiProvider::API_URL) do |f|
      f.request :json
      f.response :json
      f.adapter :test, stubs
    end

    provider = Llm::GeminiProvider.new
    with_env("LLM_MODEL" => "gemini-2.5-flash", "GEMINI_API_KEY" => "test-key") do
      result = provider.stub(:connection, fake_connection) do
        provider.generate(prompt: "describe the PR", json: true)
      end

      assert_equal "gemini", result.provider
      assert_equal 15, result.input_tokens
      assert_equal 6, result.output_tokens
      assert_equal({ "summary" => "ok" }, result.parsed_json)
    end
    stubs.verify_stubbed_calls
  end
end
