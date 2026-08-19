require "test_helper"

class Git::ParseDiffTest < ActiveSupport::TestCase
  test "classifies changed files, links to existing code entities, and dedupes hunks on the same method" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    code_entity = project.code_entities.create!(
      entity_type: "model", name: "User#full_name", class_name: "User", method_name: "full_name",
      file_path: "app/models/user.rb", signature_hash: "sig-1",
    )
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    # Two separate hunks (this is what a method touched in two different
    # places in the same file produces) both resolving to the same
    # class+method — should collapse into one ChangedCodeEntity, not two.
    changed_file = pull_request_analysis.changed_files.create!(
      file_path: "app/models/user.rb", change_type: "modified", additions: 2, deletions: 1,
      patch: <<~PATCH,
        @@ -2,4 +2,4 @@ class User < ApplicationRecord
           def full_name
        -    "\#{first_name} \#{last_name}"
        +    "\#{first_name} \#{last_name}".strip
           end
        @@ -10,3 +10,4 @@ class User < ApplicationRecord
           def full_name
             memoize_if_needed
        +    log_access
      PATCH
    )

    result = Git::ParseDiff.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    assert_equal 1, result.changed_code_entities_count
    entity = pull_request_analysis.changed_code_entities.first
    assert_equal "model", entity.entity_type
    assert_equal "User", entity.class_name
    assert_equal "full_name", entity.method_name
    assert_equal code_entity.id, entity.code_entity_id
  end

  test "skips files outside recognized Rails directories" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    pull_request_analysis.changed_files.create!(
      file_path: "spec/models/user_spec.rb", change_type: "modified", additions: 1, deletions: 0,
      patch: "@@ -1,2 +1,3 @@ class UserSpec\n+  it \"works\" do; end\n",
    )

    result = Git::ParseDiff.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    assert_equal 0, result.changed_code_entities_count
  end

  test "leaves code_entity_id nil for a brand-new method not in the base index" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    pull_request_analysis.changed_files.create!(
      file_path: "app/models/user.rb", change_type: "modified", additions: 3, deletions: 0,
      patch: "@@ -5,0 +6,3 @@ class User < ApplicationRecord\n+  def archived?\n+    archived_at.present?\n+  end\n",
    )

    result = Git::ParseDiff.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    entity = pull_request_analysis.changed_code_entities.first
    assert_nil entity.code_entity_id
    assert_equal "added", entity.change_kind
  end
end
