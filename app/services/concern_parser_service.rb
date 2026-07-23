# frozen_string_literal: true

class ConcernParserService
  INCLUDE_PATTERN = /^\s*include\s+([A-Za-z][A-Za-z0-9_:]*)/.freeze

  def parse(content)
    return [] if content.blank?

    content.each_line.filter_map do |line|
      next unless (match = line.match(INCLUDE_PATTERN))

      match[1]
    end.uniq
  end

  def concern_name_from_file_path(file_path)
    basename = File.basename(file_path, ".rb")
    basename.camelize
  end
end
