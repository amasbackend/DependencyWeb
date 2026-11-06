# Parses one file's already-stored unified diff text (ChangedFile#patch,
# produced by GitDiffParser) into per-hunk, per-line structures for
# line-numbered rendering. GitDiffParser only splits/counts per FILE, and
# RubyDiffHunkScanner only extracts semantic (class/method) context from
# hunks — neither preserves old/new line numbers or a renderable line list,
# so this is new, presentation-only logic, reusing the same
# `split(/(?=^@@ )/)` hunk-splitting technique RubyDiffHunkScanner already
# uses rather than inventing a second way to do it.
class DiffPatchParser
  Line = Struct.new(:type, :old_line_no, :new_line_no, :content, keyword_init: true)
  Hunk = Struct.new(:header, :lines, keyword_init: true)

  HUNK_HEADER = /\A@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/

  def self.call(patch:)
    new(patch).call
  end

  def initialize(patch)
    @patch = patch.to_s
  end

  def call
    hunk_blocks.map { |block| parse_hunk(block) }
  end

  private

  # Patch text starts with `diff --git`/`index`/`---`/`+++` header lines
  # before the first `@@` hunk — split those off, keep only hunk bodies.
  def hunk_blocks
    @patch.split(/(?=^@@ )/).select { |block| block.start_with?("@@") }
  end

  def parse_hunk(block)
    lines = block.lines
    header = lines.first.to_s.chomp
    match = HUNK_HEADER.match(header)
    old_line_no = match ? match[1].to_i : 0
    new_line_no = match ? match[2].to_i : 0

    parsed_lines = lines.drop(1).filter_map do |line|
      next nil if line.start_with?("\\") # "\ No newline at end of file"

      case line[0]
      when "+"
        Line.new(type: "add", new_line_no: new_line_no, content: line[1..].to_s.chomp).tap { new_line_no += 1 }
      when "-"
        Line.new(type: "remove", old_line_no: old_line_no, content: line[1..].to_s.chomp).tap { old_line_no += 1 }
      else
        Line.new(type: "context", old_line_no: old_line_no, new_line_no: new_line_no, content: line[1..].to_s.chomp)
          .tap { old_line_no += 1; new_line_no += 1 }
      end
    end

    Hunk.new(header: header, lines: parsed_lines)
  end
end
