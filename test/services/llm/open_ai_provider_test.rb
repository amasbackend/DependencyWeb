require "test_helper"

class Llm::OpenAiProviderTest < ActiveSupport::TestCase
  test "parses content and usage from a real-shaped OpenAI response" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do
        [
          200,
          { "Content-Type" => "application/json" },
          {
            model: "gpt-4.1",
            choices: [ { message: { content: '{"summary":"ok"}' } } ],
            usage: { prompt_tokens: 12, completion_tokens: 5 },
          }.to_json,
        ]
      end
    end
    fake_connection = Faraday.new(url: Llm::OpenAiProvider::API_URL) do |f|
      f.request :json
      f.response :json
      f.adapter :test, stubs
    end

    provider = Llm::OpenAiProvider.new
    with_env("LLM_MODEL" => "gpt-4.1", "OPENAI_API_KEY" => "test-key") do
      result = provider.stub(:connection, fake_connection) do
        provider.generate(prompt: "describe the PR", json: true)
      end

      assert_equal "openai", result.provider
      assert_equal 12, result.input_tokens
      assert_equal 5, result.output_tokens
      assert_equal({ "summary" => "ok" }, result.parsed_json)
    end
    stubs.verify_stubbed_calls
  end
end
