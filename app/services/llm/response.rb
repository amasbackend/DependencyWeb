module Llm
  # Uniform shape every provider returns, regardless of vendor — callers
  # never need to know whether OpenAI/Claude/Gemini answered (per user
  # request: switching provider is a config change, not a code change).
  Response = Struct.new(:content, :input_tokens, :output_tokens, :provider, :model, keyword_init: true) do
    def parsed_json
      # Providers are instructed to respond with JSON only, but models
      # occasionally wrap it in ```json fences despite that — strip them
      # before parsing rather than failing on well-formed-but-fenced output.
      JSON.parse(content.to_s.strip.delete_prefix("```json").delete_prefix("```").delete_suffix("```").strip)
    end
  end
end
