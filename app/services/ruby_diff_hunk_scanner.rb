# Extracts structured per-hunk info from a unified diff patch (§28: Diff
# Parser — feed Graphify/LLM structured data, not a raw diff blob).
#
# Class/method context comes from TWO sources, scanned in order so later
# (more specific) matches override earlier ones:
#   1. git's own hunk-header trailer (`@@ ... @@ class Foo` / `def bar`) —
#      git's built-in funcname detection, the only source when the
#      enclosing definition is too far away to appear in the 3-line context
#      window at all.
#   2. the hunk body itself (context/added/removed lines) — confirmed
#      against a real diff that git's header trailer alone can point at the
#      WRONG enclosing method when a hunk starts right before its actual
#      target (e.g. at a blank line just before `def show`, where the
#      header falls back to an earlier, unrelated `def index`) — the real
#      target method still reliably appears as context *within* the hunk
#      body in that case, so scanning the body and letting it override the
#      header catches what the header alone gets wrong.
class RubyDiffHunkScanner
  CLASS_LINE = /\A\s*(?:class|module)\s+([\w:]+)/
  DEF_LINE = /\A\s*def\s+(?:self\.)?([\w?!=\[\]<>+\-\/%]+)/
  HEADER_TRAILER = /\A@@ .+? @@ ?(.*)$/
  VALIDATION_LINE = /\bvalidates?\b/
  ASSOCIATION_LINE = /\b(?:has_many|has_one|belongs_to|has_and_belongs_to_many)\b/

  Hunk = Struct.new(:class_name, :method_name, :change_kind, :validation_changed, :association_changed, keyword_init: true)

  def self.call(patch:)
    new(patch).call
  end

  def initialize(patch)
    @patch = patch.to_s
  end

  def call
    hunks.map { |hunk| analyze(hunk) }
  end

  private

  def hunks
    @patch.split(/(?=^@@ )/).select { |h| h.start_with?("@@") }
  end

  def analyze(hunk)
    lines = hunk.lines
    header_trailer = lines.first.to_s[HEADER_TRAILER, 1]

    class_name = nil
    method_name = nil
    [ header_trailer, *lines.drop(1) ].each do |line|
      next if line.nil?

      content = line.sub(/\A[+\- ]/, "")
      if (m = CLASS_LINE.match(content))
        class_name = m[1]
      elsif (m = DEF_LINE.match(content))
        method_name = m[1]
      end
    end

    validation_changed = false
    association_changed = false
    lines.each do |line|
      next unless line.start_with?("+") || line.start_with?("-")

      content = line.sub(/\A[+\-]/, "")
      validation_changed ||= VALIDATION_LINE.match?(content)
      association_changed ||= ASSOCIATION_LINE.match?(content)
    end

    Hunk.new(
      class_name: class_name, method_name: method_name, change_kind: change_kind_for(hunk),
      validation_changed: validation_changed, association_changed: association_changed,
    )
  end

  def change_kind_for(hunk)
    lines = hunk.lines
    added = lines.any? { |l| l.start_with?("+") && !l.start_with?("+++") }
    removed = lines.any? { |l| l.start_with?("-") && !l.start_with?("---") }
    return "added" if added && !removed
    return "removed" if removed && !added

    "modified"
  end
end
