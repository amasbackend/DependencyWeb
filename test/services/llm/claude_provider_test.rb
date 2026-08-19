require "test_helper"

class Llm::ClaudeProviderTest < ActiveSupport::TestCase
  test "parses content and usage from a real-shaped Claude response" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") do
        [
          200,
          { "Content-Type" => "application/json" },
          {
            model: "claude-sonnet-4-5",
            content: [ { type: "text", text: '{"summary":"ok"}' } ],
            usage: { input_tokens: 20, output_tokens: 8 },
          }.to_json,
        ]
      end
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) do |f|
      f.request :json
      f.response :json
      f.adapter :test, stubs
    end

    provider = Llm::ClaudeProvider.new
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      result = provider.stub(:connection, fake_connection) do
        provider.generate(prompt: "describe the PR", system: "You are helpful.", json: true)
      end

      assert_equal "claude", result.provider
      assert_equal 20, result.input_tokens
      assert_equal 8, result.output_tokens
      assert_equal({ "summary" => "ok" }, result.parsed_json)
    end
    stubs.verify_stubbed_calls
  end
end
