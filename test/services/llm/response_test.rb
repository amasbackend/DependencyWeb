require "test_helper"

class Llm::ResponseTest < ActiveSupport::TestCase
  test "parsed_json parses plain JSON content" do
    response = Llm::Response.new(content: '{"a":1}')
    assert_equal({ "a" => 1 }, response.parsed_json)
  end

  test "parsed_json strips markdown code fences some models add despite instructions" do
    response = Llm::Response.new(content: "```json\n{\"a\":1}\n```")
    assert_equal({ "a" => 1 }, response.parsed_json)
  end
end
