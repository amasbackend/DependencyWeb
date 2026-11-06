module Llm
  # Estimates what an LLM call cost from the token counts the provider
  # returned — no provider's chat API returns a price, so this is token count
  # × unit price, and it's labelled 估算 wherever it's shown. Actual billing
  # (rounding, discounts, tiers) can differ; the provider's billing page is
  # the source of truth.
  #
  # Unit prices are USD per 1M tokens. Only models whose price was checked
  # against the provider's official pricing are listed; any other model gets
  # no estimate (nil) rather than a guessed one, unless prices are supplied
  # via ENV (LLM_PRICE_INPUT_PER_MTOK / LLM_PRICE_CACHED_INPUT_PER_MTOK /
  # LLM_PRICE_OUTPUT_PER_MTOK), which take precedence for every model.
  class Pricing
    USD_PER_MILLION_TOKENS = {
      # https://developers.openai.com/api/docs/models/gpt-4.1 (checked 2026/10/21)
      "gpt-4.1" => { input: 2.00, cached_input: 0.50, output: 8.00 },
    }.freeze

    # model name as the provider echoes it back (e.g. "gpt-4.1-2025-04-14")
    # => { input:, cached_input:, output: } or nil. Exact name first, then
    # the dated-snapshot form of a listed model.
    def self.for(model)
      return env_override if env_override

      model = model.to_s
      USD_PER_MILLION_TOKENS[model] ||
        USD_PER_MILLION_TOKENS.find { |name, _| model.match?(/\A#{Regexp.escape(name)}-\d{4}-\d{2}-\d{2}\z/) }&.last
    end

    # USD (BigDecimal), or nil when the model has no known price.
    def self.cost_usd(model:, input_tokens:, cached_input_tokens:, output_tokens:)
      price = self.for(model)
      return nil unless price

      cached = cached_input_tokens.to_i
      uncached = [ input_tokens.to_i - cached, 0 ].max
      total = uncached * price[:input] + cached * (price[:cached_input] || price[:input]) + output_tokens.to_i * price[:output]
      (BigDecimal(total.to_s) / 1_000_000).round(6)
    end

    # TWD per USD for display; deliberately not defaulted — an exchange rate
    # is an accounting choice, so it must be configured (LLM_USD_TWD_RATE).
    def self.usd_to_twd_rate
      ENV["LLM_USD_TWD_RATE"].presence&.to_d
    end

    def self.env_override
      input = ENV["LLM_PRICE_INPUT_PER_MTOK"].presence
      output = ENV["LLM_PRICE_OUTPUT_PER_MTOK"].presence
      return nil unless input && output

      { input: input.to_f, cached_input: ENV["LLM_PRICE_CACHED_INPUT_PER_MTOK"].presence&.to_f, output: output.to_f }
    end
    private_class_method :env_override
  end
end
