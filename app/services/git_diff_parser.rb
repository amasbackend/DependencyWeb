# Parses `git diff --name-status` (for an unambiguous file list — status
# plus, for renames, both old and new paths) and the corresponding full
# unified diff (for per-file patch text) into ChangedFile-shaped attribute
# hashes. Deliberately avoids `git diff --numstat`'s rename output, which
# encodes old/new paths ambiguously in a single field (`old => new`) — NUL-
# separated `--name-status -z` gives old/new as genuinely separate fields
# instead. Additions/deletions are counted directly from each file's own
# patch text rather than parsed from numstat at all, sidestepping the
# ambiguity entirely.
class GitDiffParser
  STATUS_MAP = {
    "A" => "added",
    "M" => "modified",
    "D" => "deleted",
    "R" => "renamed",
    "C" => "renamed", # copy — closest fit in our change_type enum
    "T" => "modified", # type change (e.g. file -> symlink)
  }.freeze

  def self.call(name_status_z:, full_diff:)
    new(name_status_z, full_diff).call
  end

  def initialize(name_status_z, full_diff)
    @name_status_fields = name_status_z.split("\0").reject(&:empty?)
    @patches_by_new_path = split_patches(full_diff)
  end

  def call
    files = []
    index = 0
    while index < @name_status_fields.length
      status = @name_status_fields[index]
      letter = status[0]

      if letter == "R" || letter == "C"
        old_path = @name_status_fields[index + 1]
        new_path = @name_status_fields[index + 2]
        index += 3
      else
        old_path = nil
        new_path = @name_status_fields[index + 1]
        index += 2
      end

      patch = @patches_by_new_path[new_path]
      additions, deletions = count_changes(patch)

      files << {
        file_path: new_path,
        previous_file_path: old_path,
        change_type: STATUS_MAP.fetch(letter, "modified"),
        additions: additions,
        deletions: deletions,
        patch: patch,
        binary: patch.present? && patch.include?("Binary files"),
      }
    end
    files
  end

  private

  def split_patches(full_diff)
    full_diff.split(/^diff --git /).drop(1).each_with_object({}) do |block, hash|
      path = block[%r{a/.+? b/(.+?)\n}, 1] || block[/\A.+? (?:b\/)?(.+?)\n/, 1]
      hash[path] = "diff --git #{block}" if path
    end
  end

  def count_changes(patch)
    return [ 0, 0 ] if patch.blank?

    lines = patch.lines
    additions = lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
    deletions = lines.count { |l| l.start_with?("-") && !l.start_with?("---") }
    [ additions, deletions ]
  end
end
