require "test_helper"

class Llm::ClaudeCliProviderTest < ActiveSupport::TestCase
  FakeStatus = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  # Trimmed from a real `claude -p --output-format json` answer.
  def cli_output(result: '{"summary":"ok"}', is_error: false)
    {
      type: "result", subtype: is_error ? "error_during_execution" : "success", is_error: is_error, result: result,
      usage: { input_tokens: 20, cache_creation_input_tokens: 946, cache_read_input_tokens: 30, output_tokens: 8 },
      modelUsage: {
        "claude-haiku-5-5" => { inputTokens: 966, outputTokens: 16, costUSD: 0.0001 },
        "claude-sonnet-5-5" => { inputTokens: 20, outputTokens: 8, costUSD: 0.0039 },
      },
    }.to_json
  end

  test "parses content, usage and the answering model from the CLI's JSON output" do
    provider = Llm::ClaudeCliProvider.new
    result = Open3.stub(:capture3, [ cli_output, "", FakeStatus.new(0) ]) do
      with_env("LLM_MODEL" => "sonnet") { provider.generate(prompt: "describe the PR", json: true) }
    end

    assert_equal "claude_cli", result.provider
    assert_equal "claude-sonnet-5-5", result.model # not the cheaper background Haiku call
    assert_equal 996, result.input_tokens # cache reads/writes count toward total input
    assert_equal 30, result.cached_input_tokens
    assert_equal 8, result.output_tokens
    assert_equal({ "summary" => "ok" }, result.parsed_json)
  end

  test "sends the prompt on stdin, the system prompt as a flag, and never the API key" do
    seen = nil
    capture = ->(*args, **opts) { seen = { args: args, opts: opts }; [ cli_output, "", FakeStatus.new(0) ] }

    provider = Llm::ClaudeCliProvider.new
    Open3.stub(:capture3, capture) do
      with_env("LLM_MODEL" => "sonnet", "CLAUDE_CLI_PATH" => "/opt/claude") do
        provider.generate(prompt: "x", system: "You are helpful.", json: true)
      end
    end

    env, binary, *flags = seen[:args]
    assert_equal "/opt/claude", binary
    assert env.key?("ANTHROPIC_API_KEY")
    assert_nil env["ANTHROPIC_API_KEY"]
    assert_equal "You are helpful.", flags[flags.index("--system-prompt") + 1]
    assert_equal "sonnet", flags[flags.index("--model") + 1]
    assert_equal "", flags[flags.index("--tools") + 1]
    assert_equal "x#{Llm::ClaudeCliProvider::JSON_INSTRUCTION}", seen[:opts][:stdin_data]
  end

  test "passes --effort only when LLM_EFFORT is set" do
    seen_flags = []
    capture = ->(*args, **) { seen_flags << args.drop(2); [ cli_output, "", FakeStatus.new(0) ] }

    provider = Llm::ClaudeCliProvider.new
    Open3.stub(:capture3, capture) do
      with_env("LLM_MODEL" => "opus", "LLM_EFFORT" => "high") { provider.generate(prompt: "x") }
      with_env("LLM_MODEL" => "opus", "LLM_EFFORT" => nil) { provider.generate(prompt: "x") }
    end

    assert_equal "high", seen_flags.first[seen_flags.first.index("--effort") + 1]
    assert_not_includes seen_flags.last, "--effort"
  end

  test "raises Provider::Error with the CLI's own message when it reports an error" do
    provider = Llm::ClaudeCliProvider.new
    error = assert_raises(Llm::Provider::Error) do
      Open3.stub(:capture3, [ cli_output(result: "Claude AI usage limit reached", is_error: true), "", FakeStatus.new(1) ]) do
        with_env("LLM_MODEL" => "sonnet") { provider.generate(prompt: "x") }
      end
    end

    assert_includes error.message, "usage limit reached"
  end

  test "raises Provider::Error when the CLI output is not JSON" do
    provider = Llm::ClaudeCliProvider.new
    error = assert_raises(Llm::Provider::Error) do
      Open3.stub(:capture3, [ "", "Invalid API key · Please run /login", FakeStatus.new(1) ]) do
        with_env("LLM_MODEL" => "sonnet") { provider.generate(prompt: "x") }
      end
    end

    assert_includes error.message, "Please run /login"
  end

  test "raises Provider::Error when the claude binary is missing" do
    provider = Llm::ClaudeCliProvider.new
    assert_raises(Llm::Provider::Error) do
      Open3.stub(:capture3, ->(*) { raise Errno::ENOENT }) do
        with_env("LLM_MODEL" => "sonnet") { provider.generate(prompt: "x") }
      end
    end
  end
end
