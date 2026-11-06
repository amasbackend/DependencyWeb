module Llm
  # SHA256 over TestScopeInputBuilder's already-deterministic output — lets
  # two TestReport rows (the same PR re-analyzed, or the same evidence sent
  # to a different provider) be compared for "did they actually see the same
  # input" without re-diffing the full evidence payload each time.
  # TestScopeInputBuilder's field order is already stable by construction
  # (fixed hash-literal key order, evidence.each in id order — see its own
  # docs), so this only needs a stable serialization on top of that, not a
  # second ordering pass.
  class EvidenceHash
    def self.call(input)
      Digest::SHA256.hexdigest(JSON.generate(input))
    end
  end
end
