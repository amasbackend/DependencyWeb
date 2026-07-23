# frozen_string_literal: true

class PrFileClassifierService
  CATEGORIES = %w[actor model controller migration route concern blueprint other].freeze

  def classify_filename(filename)
    return "concern" if filename.match?(%r{^app/actors/concerns/})
    return "actor" if filename.match?(%r{^app/actors/.*\.rb$})
    return "model" if filename.match?(%r{^app/models/[^/]+\.rb$})
    return "controller" if filename.match?(%r{^app/controllers/.*_controller\.rb$})
    return "migration" if filename.match?(%r{^db/migrate/.*\.rb$})
    return "route" if filename == "config/routes.rb"
    return "blueprint" if filename.match?(%r{^app/blueprints/.*\.rb$})

    "other"
  end

  def classify_files(files)
    grouped = CATEGORIES.index_with { [] }

    Array(files).each do |file|
      filename = file.is_a?(Hash) ? file["filename"] : file.to_s
      category = classify_filename(filename)
      entry = {
        filename: filename,
        status: file.is_a?(Hash) ? file["status"] : "modified",
        patch: file.is_a?(Hash) ? file["patch"] : nil,
        category: category,
      }
      grouped[category] << entry
    end

    grouped
  end

  def controller_path_from_file(filename)
    match = filename.match(%r{^app/controllers/(.+)_controller\.rb$})
    return nil unless match

    match[1]
  end
end
