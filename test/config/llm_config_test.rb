require "test_helper"

class LlmConfigTest < ActiveSupport::TestCase
  test "temperature is nil when LLM_TEMPERATURE is not set" do
    with_env("LLM_TEMPERATURE" => nil) { assert_nil LlmConfig.temperature }
  end

  test "temperature parses LLM_TEMPERATURE as a float" do
    with_env("LLM_TEMPERATURE" => "0.15") { assert_equal 0.15, LlmConfig.temperature }
  end
end
