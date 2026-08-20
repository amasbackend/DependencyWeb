module Impacts
  # Second half of the `mapping_features` stage (run right after
  # Impacts::MapCodeEntities): resolves each code-entity-level ImpactItem to
  # the BusinessFeature(s) it belongs to, via the FeatureCodeEntity links
  # Phase 6 already built (§17 — Feature ↔ Code Entity). A code entity can
  # legitimately back more than one feature (e.g. a shared model), so a
  # single-feature match updates the row in place; a multi-feature match
  # duplicates the row per feature (each duplicate keeps the same evidence —
  # it's the same underlying code change, just relevant to more than one
  # feature); a zero-feature match leaves business_feature_id nil and flags
  # needs_manual_review, per §36 — never guess a feature that isn't backed by
  # a real FeatureCodeEntity link.
  class MapBusinessFeatures < Actor
    input :pull_request_analysis
    output :impact_items_count

    def call
      PullRequestAnalysis.transaction do
        pull_request_analysis.impact_items.where(business_feature_id: nil).find_each { |item| resolve(item) }
      end

      self.impact_items_count = pull_request_analysis.impact_items.count
    rescue StandardError => e
      fail_with(I18n.t("actor.impacts.map_business_features.failed", message: e.message))
    end

    private

    def resolve(item)
      features = features_for(item)

      if features.empty?
        item.update!(needs_manual_review: true)
        return
      end

      first, *rest = features
      item.update!(business_feature_id: first.id)
      rest.each { |feature| item.dup.update!(business_feature_id: feature.id) }
    end

    def features_for(item)
      return BusinessFeature.none unless item.code_entity_id

      BusinessFeature.joins(:feature_code_entities)
        .where(feature_code_entities: { code_entity_id: item.code_entity_id })
        .distinct
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "mapping_features")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
