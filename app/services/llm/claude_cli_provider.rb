require "open3"

module Llm
  # Answers through the local `claude` CLI (Claude Code's headless `-p` mode)
  # instead of an HTTP API, so usage counts against whichever claude.ai
  # account that CLI is logged into (check with `claude auth status`) — a
  # Pro/Max/Team seat's usage limits, not pay-as-you-go API billing. The CLI
  # must be logged in as the same OS user the Rails process runs as.
  #
  # ANTHROPIC_API_KEY is stripped from the child's environment: the CLI
  # prefers it over the logged-in account when present, which would silently
  # move this provider onto API billing.
  #
  # No #with_retry here — the CLI already retries 429/5xx/overloaded API
  # responses itself before exiting. temperature is ignored: the CLI has no
  # flag for it.
  class ClaudeCliProvider < Provider
    JSON_INSTRUCTION = "\n\nRespond with valid JSON only — no prose, no markdown code fences.".freeze

    def generate(prompt:, system: nil, json: false, temperature: nil)
      stdout, stderr, status = run_cli(json ? "#{prompt}#{JSON_INSTRUCTION}" : prompt, system)
      body = parse(stdout)
      if body.nil? || body["is_error"] || !status.success?
        raise Provider::Error, "Claude CLI error (exit #{status.exitstatus}): #{body&.dig('result').presence || stderr.presence || stdout}"
      end

      usage = body.fetch("usage", {})

      Llm::Response.new(
        content: body.fetch("result"),
        # Same summing as ClaudeProvider — the CLI reports Anthropic's own
        # usage block, with cache reads/writes outside input_tokens.
        input_tokens: usage["input_tokens"] && usage["input_tokens"] + usage["cache_read_input_tokens"].to_i + usage["cache_creation_input_tokens"].to_i,
        cached_input_tokens: usage["cache_read_input_tokens"],
        output_tokens: usage["output_tokens"],
        provider: "claude_cli",
        model: answering_model(body),
      )
    end

    private

    # The prompt goes in on stdin, not argv — a batch prompt can be ~100KB,
    # close to Linux's 128KB single-argument limit. Run from a tmpdir with no
    # setting sources, tools or MCP servers, so nothing from this repo (or
    # the user's Claude Code setup) leaks into the request.
    def run_cli(prompt, system)
      args = [
        "-p", "--output-format", "json", "--model", LlmConfig.model,
        "--tools", "", "--strict-mcp-config", "--setting-sources", "", "--no-session-persistence",
      ]
      args += [ "--system-prompt", system ] if system.present?
      args += [ "--effort", LlmConfig.effort ] if LlmConfig.effort

      Open3.capture3({ "ANTHROPIC_API_KEY" => nil, "CLAUDECODE" => nil }, LlmConfig.claude_cli_path, *args,
                     stdin_data: prompt, chdir: Dir.tmpdir)
    rescue Errno::ENOENT
      raise Provider::Error, "claude command not found (#{LlmConfig.claude_cli_path}) — install Claude Code or set CLAUDE_CLI_PATH"
    end

    def parse(stdout)
      JSON.parse(stdout)
    rescue JSON::ParserError
      nil
    end

    # modelUsage also lists small background calls the CLI makes on its own
    # (e.g. a Haiku title request); the answering model is the one that cost
    # the most. Its key is the full model name even when LLM_MODEL is an
    # alias like "opus".
    def answering_model(body)
      body.fetch("modelUsage", {}).max_by { |_, u| u["costUSD"].to_f }&.first || LlmConfig.model
    end
  end
end
