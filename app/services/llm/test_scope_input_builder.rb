module Llm
  # Assembles the deterministic, evidence-only input for §35's translation
  # step (technical change → operator test scope) — never the whole
  # repository (§34/§62's cost-control rule). Every field here traces back
  # to a real row Phases 8-11 already computed; the LLM never sees anything
  # this class didn't put in front of it.
  #
  # Each impact item gets a short reference token ("IMPACT-3") so the LLM's
  # response can cite *which* already-computed evidence a test case is
  # grounded in — Llm::AnalyzeTestScope resolves these back to real
  # ImpactItem ids after the response comes back, rather than trying to
  # fuzzy-match free text (§36 — traceable, not guessed).
  class TestScopeInputBuilder
    Result = Struct.new(:input, :ref_to_impact_item_id, keyword_init: true)

    # A full raw patch can be large (this is exactly why graphify_artifacts/
    # changed_files.patch needed LONGTEXT — see docs/architecture_plan.md §10
    # Phase 10 notes) — an excerpt is enough for the LLM to see the shape of
    # a change; ChangedCodeEntity already carries the structured signal
    # (class/method/validation/association) so the excerpt is a supplement,
    # not the primary evidence.
    PATCH_EXCERPT_LIMIT = 2000

    def self.call(pull_request_analysis)
      builder = new(pull_request_analysis)
      Result.new(input: builder.build, ref_to_impact_item_id: builder.ref_to_impact_item_id)
    end

    def initialize(pull_request_analysis)
      @pull_request_analysis = pull_request_analysis
      @project = pull_request_analysis.project
      @ref_to_impact_item_id = {}
    end

    attr_reader :ref_to_impact_item_id

    def build
      {
        project: project_info,
        pull_request: pr_info,
        changed_files: changed_files_info,
        changed_code_entities: changed_code_entities_info,
        impact_items: impact_items_info,
        known_features: known_features,
      }
    end

    private

    attr_reader :pull_request_analysis, :project

    def project_info
      { owner: project.owner, repository_name: project.repository_name }
    end

    def pr_info
      {
        pr_number: pull_request_analysis.pr_number,
        title: pull_request_analysis.pr_title,
        description: pull_request_analysis.pr_description,
        author: pull_request_analysis.pr_author,
        base_branch: pull_request_analysis.base_branch,
        head_branch: pull_request_analysis.head_branch,
      }
    end

    def changed_files_info
      pull_request_analysis.changed_files.map do |f|
        {
          file_path: f.file_path, change_type: f.change_type, additions: f.additions, deletions: f.deletions,
          patch_excerpt: f.patch.to_s.truncate(PATCH_EXCERPT_LIMIT),
        }
      end
    end

    def changed_code_entities_info
      pull_request_analysis.changed_code_entities.map do |e|
        {
          entity_type: e.entity_type, class_name: e.class_name, method_name: e.method_name,
          change_kind: e.change_kind, validation_changed: e.validation_changed, association_changed: e.association_changed,
        }
      end
    end

    def impact_items_info
      pull_request_analysis.impact_items.includes(:business_feature, :code_entity).order(:id).each_with_index.map do |item, index|
        ref = "IMPACT-#{index + 1}"
        ref_to_impact_item_id[ref] = item.id

        {
          ref: ref,
          impact_level: item.impact_level,
          code_entity: item.code_entity && [ item.code_entity.class_name, item.code_entity.method_name ].compact.join("#"),
          business_module: item.business_feature&.business_module&.name,
          business_feature: item.business_feature&.name,
          reason: item.reason,
          evidence: item.evidence,
          needs_manual_review: item.needs_manual_review,
        }
      end
    end

    # The constrained vocabulary the LLM must pick from for a test case's
    # "feature" field — never allowed to invent a business feature name that
    # isn't a real BusinessFeature this project actually has (§36).
    def known_features
      project.business_features.includes(:business_module).order(:id).map do |f|
        { module: f.business_module.name, feature: f.name }
      end
    end
  end
end
