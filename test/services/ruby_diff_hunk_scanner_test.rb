require "test_helper"

class RubyDiffHunkScannerTest < ActiveSupport::TestCase
  # This exact hunk (from a real spike against a fixture repo) demonstrates
  # why scanning the whole hunk body matters, not just git's own single-line
  # header: the header says "def index" (the last `def` line strictly
  # *before* the hunk), but the actual change is inside `show`, which only
  # appears as context *within* the hunk itself.
  test "finds the method from hunk body context, not just git's own (sometimes wrong) header" do
    patch = <<~PATCH
      @@ -5,5 +5,6 @@ def index

         def show
           @user = User.find(params[:id])
      +    @posts = @user.posts
         end
       end
    PATCH

    hunks = RubyDiffHunkScanner.call(patch: patch)

    assert_equal 1, hunks.size
    assert_equal "show", hunks.first.method_name
  end

  test "captures the enclosing class from the hunk header when no def is present" do
    patch = <<~PATCH
      @@ -3,7 +3,7 @@ class User < ApplicationRecord
         has_many :posts

         def full_name
      -    "\#{first_name} \#{last_name}"
      +    "\#{first_name} \#{last_name}".strip
         end
    PATCH

    hunks = RubyDiffHunkScanner.call(patch: patch)

    assert_equal "User", hunks.first.class_name
    assert_equal "full_name", hunks.first.method_name
  end

  test "detects validation and association changes only from added/removed lines, not context" do
    patch = <<~PATCH
      @@ -1,6 +1,7 @@ class User < ApplicationRecord
       class User < ApplicationRecord
      +  validates :email, presence: true
      +  has_many :comments
         has_many :posts
       end
    PATCH

    hunk = RubyDiffHunkScanner.call(patch: patch).first

    assert hunk.validation_changed
    assert hunk.association_changed
  end

  test "classifies a hunk that is purely additions as added" do
    patch = <<~PATCH
      @@ -10,0 +11,3 @@ class User < ApplicationRecord
      +  def archive
      +    update!(archived: true)
      +  end
    PATCH

    hunk = RubyDiffHunkScanner.call(patch: patch).first

    assert_equal "added", hunk.change_kind
  end

  test "returns one entry per hunk in a multi-hunk patch" do
    patch = <<~PATCH
      @@ -3,3 +3,3 @@ class User < ApplicationRecord
         def full_name
      -    "\#{first_name} \#{last_name}"
      +    "\#{first_name} \#{last_name}".strip
         end
      @@ -10,3 +10,4 @@ class User < ApplicationRecord
         def greeting
           "Hello"
      +    # extra line
         end
    PATCH

    hunks = RubyDiffHunkScanner.call(patch: patch)

    assert_equal 2, hunks.size
    assert_equal %w[full_name greeting], hunks.map(&:method_name)
  end
end
