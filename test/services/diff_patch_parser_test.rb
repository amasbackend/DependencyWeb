require "test_helper"

class DiffPatchParserTest < ActiveSupport::TestCase
  FIXTURE = <<~PATCH
    diff --git a/app/models/order.rb b/app/models/order.rb
    index abc123..def456 100644
    --- a/app/models/order.rb
    +++ b/app/models/order.rb
    @@ -1,4 +1,5 @@
     class Order < ApplicationRecord
    -  belongs_to :customer
    +  belongs_to :customer, optional: true
    +  has_many :line_items
     end
  PATCH

  test "splits the patch into one hunk with a parsed header" do
    hunks = DiffPatchParser.call(patch: FIXTURE)

    assert_equal 1, hunks.size
    assert_equal "@@ -1,4 +1,5 @@", hunks.first.header
  end

  test "classifies each line as add/remove/context with correct old/new line numbers" do
    lines = DiffPatchParser.call(patch: FIXTURE).first.lines

    assert_equal "context", lines[0].type
    assert_equal 1, lines[0].old_line_no
    assert_equal 1, lines[0].new_line_no
    assert_equal "class Order < ApplicationRecord", lines[0].content

    assert_equal "remove", lines[1].type
    assert_equal 2, lines[1].old_line_no
    assert_nil lines[1].new_line_no
    assert_equal "  belongs_to :customer", lines[1].content

    assert_equal "add", lines[2].type
    assert_equal 2, lines[2].new_line_no
    assert_nil lines[2].old_line_no
    assert_equal "  belongs_to :customer, optional: true", lines[2].content

    assert_equal "add", lines[3].type
    assert_equal 3, lines[3].new_line_no

    assert_equal "context", lines[4].type
    assert_equal 3, lines[4].old_line_no
    assert_equal 4, lines[4].new_line_no
  end

  test "handles multiple hunks in one patch" do
    patch = <<~PATCH
      diff --git a/app/models/order.rb b/app/models/order.rb
      index abc123..def456 100644
      --- a/app/models/order.rb
      +++ b/app/models/order.rb
      @@ -1,2 +1,2 @@
       class Order
      -end
      +end # first
      @@ -10,2 +10,2 @@
       class Other
      -end
      +end # second
    PATCH

    hunks = DiffPatchParser.call(patch: patch)

    assert_equal 2, hunks.size
    assert_equal "@@ -1,2 +1,2 @@", hunks[0].header
    assert_equal "@@ -10,2 +10,2 @@", hunks[1].header
    assert_equal 10, hunks[1].lines.first.old_line_no
  end

  test "ignores a trailing no-newline marker line" do
    patch = <<~PATCH.chomp
      diff --git a/x.rb b/x.rb
      --- a/x.rb
      +++ b/x.rb
      @@ -1,1 +1,1 @@
      -old
      \\ No newline at end of file
      +new
      \\ No newline at end of file
    PATCH

    lines = DiffPatchParser.call(patch: patch).first.lines

    assert_equal 2, lines.size
    assert_equal %w[remove add], lines.map(&:type)
  end

  test "returns no hunks for a blank patch" do
    assert_equal [], DiffPatchParser.call(patch: nil)
    assert_equal [], DiffPatchParser.call(patch: "")
  end
end
