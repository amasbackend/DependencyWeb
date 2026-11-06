require "test_helper"

# Closes the one real gap confirmed in the LLM pipeline's cross-provider
# story: Llm::Provider/TestScopePrompt/TestScopeInputBuilder/TestScopeSchema
# were already provider-agnostic (one shared prompt, one deterministic input
# builder, one validator — see Llm::ProviderTest and each *_provider_test.rb),
# but no test had ever driven the *same* evidence through all three vendors
# and checked they land on the same contract. This does exactly that: one
# real TestScopeInputBuilder batch, one prompt built from it, stubbed at
# each vendor's own HTTP shape (their per-provider test files already prove
# each shape parses correctly in isolation — this proves the shared contract
# holds across all three at once, not each vendor's own parsing).
class Llm::CrossProviderConsistencyTest < ActiveSupport::TestCase
  def build_pull_request_analysis
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pra = project.pull_request_analyses.create!(pr_number: 65, status: "mapping_features")
    changed_file = pra.changed_files.create!(file_path: "app/actors/orders/validate.rb", change_type: "modified", additions: 3, deletions: 1)
    cce = pra.changed_code_entities.create!(
      changed_file: changed_file, entity_type: "actor", class_name: "Orders::Validate", method_name: "check_qty", change_kind: "modified",
    )
    pra.impact_items.create!(source_changed_code_entity: cce, impact_level: "direct_change", reason: "此 PR 直接修改：Orders::Validate#check_qty")
    pra
  end

  def build_batch
    Llm::TestScopeInputBuilder.call(build_pull_request_analysis, snapshot: screen_fixture_snapshot).chunks.first
  end

  # Three deliberately differently-worded (§61 — consistency isn't identical
  # text) but schema-valid batch answers, simulating what Claude/Gemini/OpenAI
  # might each actually answer for the exact same evidence.
  def payload_for(wording)
    {
      "chunk_summary" => [ { "type" => "錯誤修正", "description" => wording } ],
      "test_cases" => [
        {
          "name" => "#{wording} 測試", "screen_key" => "orders#new", "case_type" => "core_change",
          "impact_item_refs" => [ "CHG-1" ], "verification_purpose" => wording,
          "steps" => [ "進入「訂單管理」", "點選「送出」" ], "expected_result" => "儲存成功",
          "failure_criteria" => nil, "notes" => nil, "evidence" => [ "CHG-1" ],
        },
      ],
      "uncertain_items" => [], "preparation" => [], "manual_checks" => [],
    }
  end

  def stub_claude(payload)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/messages") do
        [ 200, { "Content-Type" => "application/json" }, { model: "claude-sonnet-4-5", content: [ { type: "text", text: payload.to_json } ], usage: { input_tokens: 100, output_tokens: 50 } }.to_json ]
      end
    end
    connection = Faraday.new(url: Llm::ClaudeProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }
    Llm::ClaudeProvider.new.tap { |p| p.define_singleton_method(:connection) { connection } }
  end

  def stub_gemini(payload)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1beta/models/gemini-2.5-flash:generateContent") do
        [ 200, { "Content-Type" => "application/json" }, { candidates: [ { content: { parts: [ { text: payload.to_json } ] } } ], usageMetadata: { promptTokenCount: 90, candidatesTokenCount: 45 } }.to_json ]
      end
    end
    connection = Faraday.new(url: Llm::GeminiProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }
    Llm::GeminiProvider.new.tap { |p| p.define_singleton_method(:connection) { connection } }
  end

  def stub_openai(payload)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do
        [ 200, { "Content-Type" => "application/json" }, { model: "gpt-4.1", choices: [ { message: { content: payload.to_json } } ], usage: { prompt_tokens: 80, completion_tokens: 40 } }.to_json ]
      end
    end
    connection = Faraday.new(url: Llm::OpenAiProvider::API_URL) { |f| f.request :json; f.response :json; f.adapter :test, stubs }
    Llm::OpenAiProvider.new.tap { |p| p.define_singleton_method(:connection) { connection } }
  end

  test "the same batch, sent to all three providers, produces schema-valid output under one shared contract" do
    batch = build_batch
    prompt = Llm::TestScopePrompt.build(batch.input)
    evidence_hash = Llm::EvidenceHash.call(batch.input)

    providers = {
      "claude" => stub_claude(payload_for("確認數量檢查是否正確")),
      "gemini" => stub_gemini(payload_for("驗證系統的數量檢查")),
      "openai" => stub_openai(payload_for("Check the quantity validation")),
    }

    # LlmConfig.model/api_key read global ENV regardless of which Provider
    # instance is calling .generate — Gemini's URL embeds the model name, so
    # it must match what its stub above registered.
    model_for = { "claude" => "claude-sonnet-4-5", "gemini" => "gemini-2.5-flash", "openai" => "gpt-4.1" }

    providers.each do |name, provider|
      with_env("LLM_PROVIDER" => name, "LLM_MODEL" => model_for.fetch(name), "ANTHROPIC_API_KEY" => "k", "GEMINI_API_KEY" => "k", "OPENAI_API_KEY" => "k") do
        data = provider.generate(system: prompt[:system], prompt: prompt[:user], json: true).parsed_json
        errors = Llm::TestScopeSchema.validate_chunk(data, screen_keys: batch.screen_keys, refs: batch.refs)

        assert_empty errors, "#{name}'s response failed schema validation: #{errors.inspect}"
        assert_equal [ "CHG-1" ], data.dig("test_cases", 0, "impact_item_refs"), "#{name} must cite the same real ref"
        assert_equal "orders#new", data.dig("test_cases", 0, "screen_key"), "#{name} must place the case on the batch's screen"
      end
    end

    assert_equal evidence_hash, Llm::EvidenceHash.call(batch.input)
  end

  test "evidence_hash is identical regardless of which provider will receive it" do
    batch = build_batch

    hash_before_claude_call = Llm::EvidenceHash.call(batch.input)
    stub_claude(payload_for("x")).generate(system: "s", prompt: "u", json: true)

    assert_equal hash_before_claude_call, Llm::EvidenceHash.call(batch.input)
  end
end
