# frozen_string_literal: true

class MigrationDiffAnalyzerService
  COLUMN_PATTERNS = [
    [/\+.*add_column\s+:(\w+),\s+:(\w+)/, "add_column"],
    [/\+.*change_column\s+:(\w+),\s+:(\w+)/, "change_column"],
    [/\+.*remove_column\s+:(\w+),\s+:(\w+)/, "remove_column"],
    [/\+.*rename_column\s+:(\w+),\s+:(\w+)/, "rename_column"],
  ].freeze

  def analyze_patch(patch)
    return [] if patch.blank?

    impacts = []
    seen = {}

    patch.each_line do |line|
      COLUMN_PATTERNS.each do |pattern, change_type|
        next unless (match = line.match(pattern))

        table = match[1]
        column = match[2]
        key = [table, column, change_type]
        next if seen[key]

        seen[key] = true
        impacts << {
          table: table,
          column: column,
          change_type: change_type,
          model_name: table.singularize.camelize,
        }
      end
    end

    impacts
  end

  def analyze_file(file_entry)
    analyze_patch(file_entry[:patch] || file_entry["patch"])
  end
end
