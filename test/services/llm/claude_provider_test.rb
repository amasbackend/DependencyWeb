require "test_helper"

class Llm::ClaudeProviderTest < ActiveSupport::TestCase
  def success_response
    [
      200,
      { "Content-Type" => "application/json" },
      { model: "claude-sonnet-4-5", content: [ { type: "text", text: '{"summary":"ok"}' } ], usage: {} }.to_json,
    ]
  end

  test "includes temperature in the request body when given" do
    seen_body = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") { |env| seen_body = JSON.parse(env.body); success_response }
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::ClaudeProvider.new
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      provider.stub(:connection, fake_connection) { provider.generate(prompt: "x", temperature: 0.1) }
    end

    assert_equal 0.1, seen_body["temperature"]
    stubs.verify_stubbed_calls
  end

  test "omits temperature from the request body when not given" do
    seen_body = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") { |env| seen_body = JSON.parse(env.body); success_response }
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::ClaudeProvider.new
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      provider.stub(:connection, fake_connection) { provider.generate(prompt: "x") }
    end

    assert_not seen_body.key?("temperature")
    stubs.verify_stubbed_calls
  end

  test "retries once after a 5xx and succeeds on the second attempt" do
    attempt = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") do
        attempt += 1
        attempt == 1 ? [ 503, {}, "service unavailable" ] : success_response
      end
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::ClaudeProvider.new
    result = nil
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      result = provider.stub(:sleep, nil) do
        provider.stub(:connection, fake_connection) { provider.generate(prompt: "x", json: true) }
      end
    end

    assert_equal 2, attempt
    assert_equal({ "summary" => "ok" }, result.parsed_json)
  end

  test "retries a 429 rate limit with backoff and succeeds" do
    attempt = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") do
        attempt += 1
        attempt == 1 ? [ 429, {}, "rate limited" ] : success_response
      end
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::ClaudeProvider.new
    result = nil
    slept_for = []
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      result = provider.stub(:sleep, ->(seconds) { slept_for << seconds }) do
        provider.stub(:connection, fake_connection) { provider.generate(prompt: "x", json: true) }
      end
    end

    assert_equal 2, attempt
    assert_equal [ Llm::Provider::BACKOFF_SECONDS ], slept_for
    assert_equal({ "summary" => "ok" }, result.parsed_json)
  end

  test "gives up after MAX_ATTEMPTS consecutive 5xx responses and raises Provider::Error" do
    attempt = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") { attempt += 1; [ 503, {}, "service unavailable" ] }
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::ClaudeProvider.new
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      assert_raises(Llm::Provider::Error) do
        provider.stub(:sleep, nil) { provider.stub(:connection, fake_connection) { provider.generate(prompt: "x") } }
      end
    end

    assert_equal Llm::Provider::MAX_ATTEMPTS, attempt
  end

  test "does not retry a 4xx — fails immediately on the first attempt" do
    attempt = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") { attempt += 1; [ 401, {}, "unauthorized" ] }
    end
    fake_connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }

    provider = Llm::ClaudeProvider.new
    with_env("LLM_MODEL" => "claude-sonnet-4-5", "ANTHROPIC_API_KEY" => "test-key") do
      assert_raises(Llm::Provider::Error) do
        provider.stub(:connection, fake_connection) { provider.generate(prompt: "x") }
      end
    end

    assert_equal 1, attempt
  end

  test "parses content and usage from a real-shaped Claude response" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") do
        [
          200,
          { "Content-Type" => "application/json" },
          {
            model: "claude-sonnet-4-5",
            content: [ { type: "text", text: '{"summary":"ok"}' } ],
            usage: { input_tokens: 20, output_tokens: 8, cache_read_input_tokens: 30 },
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
      assert_equal 50, result.input_tokens # cache reads count toward total input
      assert_equal 30, result.cached_input_tokens
      assert_equal 8, result.output_tokens
      assert_equal({ "summary" => "ok" }, result.parsed_json)
    end
    stubs.verify_stubbed_calls
  end
end
