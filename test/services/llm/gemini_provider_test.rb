require "test_helper"

class Llm::GeminiProviderTest < ActiveSupport::TestCase
  def success_response
    [ 200, { "Content-Type" => "application/json" }, { candidates: [ { content: { parts: [ { text: "{}" } ] } } ] }.to_json ]
  end

  test "nests temperature under generationConfig when given" do
    seen_body = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1beta/models/gemini-2.5-flash:generateContent") { |env| seen_body = JSON.parse(env.body); success_response }
    end
    fake_connection = Faraday.new(url: Llm::GeminiProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::GeminiProvider.new
    with_env("LLM_PROVIDER" => "gemini", "LLM_MODEL" => "gemini-2.5-flash", "GEMINI_API_KEY" => "test-key") do
      provider.stub(:connection, fake_connection) { provider.generate(prompt: "x", json: true, temperature: 0.2) }
    end

    assert_equal 0.2, seen_body.dig("generationConfig", "temperature")
    assert_equal "application/json", seen_body.dig("generationConfig", "responseMimeType")
    stubs.verify_stubbed_calls
  end

  test "omits generationConfig entirely when neither json nor temperature is given" do
    seen_body = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1beta/models/gemini-2.5-flash:generateContent") { |env| seen_body = JSON.parse(env.body); success_response }
    end
    fake_connection = Faraday.new(url: Llm::GeminiProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::GeminiProvider.new
    with_env("LLM_PROVIDER" => "gemini", "LLM_MODEL" => "gemini-2.5-flash", "GEMINI_API_KEY" => "test-key") do
      provider.stub(:connection, fake_connection) { provider.generate(prompt: "x") }
    end

    assert_not seen_body.key?("generationConfig")
    stubs.verify_stubbed_calls
  end

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
    with_env("LLM_PROVIDER" => "gemini", "LLM_MODEL" => "gemini-2.5-flash", "GEMINI_API_KEY" => "test-key") do
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
