require "test_helper"

class Llm::PricingTest < ActiveSupport::TestCase
  test "prices a listed model and its dated snapshot name the same way" do
    assert_equal Llm::Pricing.for("gpt-4.1"), Llm::Pricing.for("gpt-4.1-2025-04-14")
    assert_nil Llm::Pricing.for("gpt-4.1-mini"), "a different model must not inherit gpt-4.1's price by prefix"
  end

  test "bills cached input at the cached rate and the rest at the full input rate" do
    # 1M input of which 400k cached, 100k output: 600k×$2 + 400k×$0.5 + 100k×$8 per 1M = $2.20
    cost = Llm::Pricing.cost_usd(model: "gpt-4.1-2025-04-14", input_tokens: 1_000_000, cached_input_tokens: 400_000, output_tokens: 100_000)

    assert_equal BigDecimal("2.2"), cost
  end

  test "returns nil rather than a guess for a model with no known price" do
    assert_nil Llm::Pricing.cost_usd(model: "some-unknown-model", input_tokens: 10, cached_input_tokens: 0, output_tokens: 10)
  end

  test "ENV unit prices override the table for any model" do
    with_env("LLM_PRICE_INPUT_PER_MTOK" => "1", "LLM_PRICE_OUTPUT_PER_MTOK" => "4", "LLM_PRICE_CACHED_INPUT_PER_MTOK" => nil) do
      assert_equal BigDecimal("5"), Llm::Pricing.cost_usd(model: "some-unknown-model", input_tokens: 1_000_000, cached_input_tokens: 0, output_tokens: 1_000_000)
    end
  end

  test "the exchange rate is only what is configured" do
    with_env("LLM_USD_TWD_RATE" => nil) { assert_nil Llm::Pricing.usd_to_twd_rate }
    with_env("LLM_USD_TWD_RATE" => "31.5") { assert_equal BigDecimal("31.5"), Llm::Pricing.usd_to_twd_rate }
  end
end
