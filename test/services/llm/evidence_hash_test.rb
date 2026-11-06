require "test_helper"

class Llm::EvidenceHashTest < ActiveSupport::TestCase
  test "the same input always produces the same hash" do
    input = { project: { owner: "AMASTek" }, impact_items: [ { ref: "IMPACT-1" } ] }

    assert_equal Llm::EvidenceHash.call(input), Llm::EvidenceHash.call(input)
  end

  test "a different input produces a different hash" do
    a = { project: { owner: "AMASTek" } }
    b = { project: { owner: "SomeoneElse" } }

    assert_not_equal Llm::EvidenceHash.call(a), Llm::EvidenceHash.call(b)
  end

  test "returns a hex-encoded SHA256 digest" do
    hash = Llm::EvidenceHash.call({ a: 1 })

    assert_match(/\A[0-9a-f]{64}\z/, hash)
  end
end
