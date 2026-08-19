require "test_helper"

class Llm::ProviderTest < ActiveSupport::TestCase
  test "current returns the provider matching LLM_PROVIDER" do
    with_env("LLM_PROVIDER" => "openai") { assert_instance_of Llm::OpenAiProvider, Llm::Provider.current }
    with_env("LLM_PROVIDER" => "claude") { assert_instance_of Llm::ClaudeProvider, Llm::Provider.current }
    with_env("LLM_PROVIDER" => "gemini") { assert_instance_of Llm::GeminiProvider, Llm::Provider.current }
  end

  test "current raises a clear error for an unsupported provider" do
    with_env("LLM_PROVIDER" => "not-a-real-provider") do
      assert_raises(Llm::Provider::Error) { Llm::Provider.current }
    end
  end
end
