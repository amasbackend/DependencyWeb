module Git
  class ParseDiff < Actor
    input :pull_request_analysis
    output :changed_code_entities_count

    def call
      entities = pull_request_analysis.changed_files.flat_map { |file| build_entities(file) }

      PullRequestAnalysis.transaction do
        pull_request_analysis.changed_code_entities.destroy_all
        pull_request_analysis.changed_code_entities.create!(entities) if entities.any?
      end

      self.changed_code_entities_count = entities.size
    rescue StandardError => e
      fail_with(I18n.t("actor.git.parse_diff.failed", message: e.message))
    end

    private

    def build_entities(changed_file)
      return [] if changed_file.patch.blank?

      entity_type = classify(changed_file.file_path)
      return [] unless entity_type

      RubyDiffHunkScanner.call(patch: changed_file.patch)
        .reject { |hunk| hunk.class_name.blank? && hunk.method_name.blank? }
        .uniq { |hunk| [ hunk.class_name, hunk.method_name ] }
        .map { |hunk| entity_attrs(changed_file, entity_type, hunk) }
    end

    def entity_attrs(changed_file, entity_type, hunk)
      code_entity = pull_request_analysis.project.code_entities.find_by(
        entity_type: entity_type, class_name: hunk.class_name, method_name: hunk.method_name
      )

      {
        changed_file_id: changed_file.id,
        code_entity_id: code_entity&.id,
        entity_type: entity_type,
        class_name: hunk.class_name,
        method_name: hunk.method_name,
        change_kind: hunk.change_kind,
        validation_changed: hunk.validation_changed,
        association_changed: hunk.association_changed,
      }
    end

    # Reuses Phase 5's Rails-directory-convention classifier rather than
    # duplicating it — a changed file is classified the same way whether it's
    # being scanned for the base index or for a PR diff.
    def classify(file_path)
      CodeEntityExtractor::TYPE_BY_PATH_PREFIX.each { |prefix, type| return type if file_path.start_with?(prefix) }
      nil
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "diffing")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
