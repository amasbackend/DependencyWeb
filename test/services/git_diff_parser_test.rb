require "test_helper"

class GitDiffParserTest < ActiveSupport::TestCase
  def build_diff(*file_diffs)
    file_diffs.join
  end

  test "parses a modified file with its patch and computed additions/deletions" do
    name_status = "M\0app/models/user.rb\0"
    full_diff = <<~DIFF
      diff --git a/app/models/user.rb b/app/models/user.rb
      index abc123..def456 100644
      --- a/app/models/user.rb
      +++ b/app/models/user.rb
      @@ -3,3 +3,4 @@ class User < ApplicationRecord
         def full_name
      -    "\#{first_name} \#{last_name}"
      +    "\#{first_name} \#{last_name}".strip
      +    # trimmed
         end
    DIFF

    files = GitDiffParser.call(name_status_z: name_status, full_diff: full_diff)

    assert_equal 1, files.size
    file = files.first
    assert_equal "app/models/user.rb", file[:file_path]
    assert_equal "modified", file[:change_type]
    assert_nil file[:previous_file_path]
    assert_equal 2, file[:additions]
    assert_equal 1, file[:deletions]
    assert_match "def full_name", file[:patch]
  end

  test "parses a renamed file with both old and new paths, unambiguous even with '=>' in either path" do
    name_status = "R100\0app/models/old_name.rb\0app/models/new_name.rb\0"
    full_diff = <<~DIFF
      diff --git a/app/models/old_name.rb b/app/models/new_name.rb
      similarity index 100%
      rename from app/models/old_name.rb
      rename to app/models/new_name.rb
    DIFF

    files = GitDiffParser.call(name_status_z: name_status, full_diff: full_diff)

    file = files.first
    assert_equal "renamed", file[:change_type]
    assert_equal "app/models/old_name.rb", file[:previous_file_path]
    assert_equal "app/models/new_name.rb", file[:file_path]
  end

  test "parses an added file and a deleted file in the same diff" do
    name_status = "A\0app/models/new_model.rb\0D\0app/models/gone.rb\0"
    full_diff = build_diff(
      "diff --git a/app/models/new_model.rb b/app/models/new_model.rb\nnew file mode 100644\n--- /dev/null\n+++ b/app/models/new_model.rb\n@@ -0,0 +1,2 @@\n+class NewModel\n+end\n",
      "diff --git a/app/models/gone.rb b/app/models/gone.rb\ndeleted file mode 100644\n--- a/app/models/gone.rb\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-class Gone\n-end\n",
    )

    files = GitDiffParser.call(name_status_z: name_status, full_diff: full_diff)

    added = files.find { |f| f[:file_path] == "app/models/new_model.rb" }
    deleted = files.find { |f| f[:file_path] == "app/models/gone.rb" }
    assert_equal "added", added[:change_type]
    assert_equal 2, added[:additions]
    assert_equal "deleted", deleted[:change_type]
    assert_equal 2, deleted[:deletions]
  end
end
