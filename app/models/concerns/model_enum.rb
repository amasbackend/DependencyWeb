class ModelEnum
  def self.project_status_enum
    { pending: 0, importing: 1, ready: 2, syncing: 3, failed: 4 }
  end

  def self.project_analysis_status_enum
    {
      queued: 0,
      fetching_metadata: 1,
      cloning: 2,
      installing_graphify: 3,
      scanning_code: 4,
      mapping_business_modules: 5,
      mapping_business_features: 6,
      completed: 7,
      failed: 8,
    }
  end

  # Shared by BusinessModule#source and BusinessFeature#source
  def self.business_entity_source_enum
    { locale_derived: 0, route_derived: 1, llm_inferred: 2, manual: 3 }
  end

  def self.code_entity_type_enum
    {
      model: 0,
      controller: 1,
      actor: 2,
      service: 3,
      blueprint: 4,
      job: 5,
      mailer: 6,
      route: 7,
      view: 8,
      javascript: 9,
      concern: 10,
      validator: 11,
      serializer: 12,
    }
  end

  def self.feature_code_entity_role_enum
    { route: 0, controller_action: 1, actor: 2, model: 3, view: 4, other: 5 }
  end

  def self.feature_code_entity_source_enum
    { rule_based: 0, llm_inferred: 1, manual: 2 }
  end

  def self.pull_request_analysis_status_enum
    {
      queued: 0,
      fetching_pr: 1,
      creating_workspace: 2,
      diffing: 3,
      graphifying: 4,
      mapping_features: 5,
      llm_analyzing: 6,
      building_report: 7,
      completed: 8,
      failed: 9,
      llm_failed: 10,
    }
  end

  def self.changed_file_change_type_enum
    { added: 0, modified: 1, deleted: 2, renamed: 3 }
  end

  def self.changed_code_entity_change_kind_enum
    { added: 0, modified: 1, removed: 2 }
  end

  def self.impact_item_level_enum
    {
      direct_change: 0,
      direct_dependency: 1,
      indirect_dependency: 2,
      regression_candidate: 3,
    }
  end

  def self.test_report_status_enum
    { generating: 0, completed: 1, failed: 2 }
  end

  def self.test_case_type_enum
    { core_change: 0, direct_impact: 1, indirect_impact: 2, regression: 3 }
  end

  # Evidence tier behind one OperatorPathSegment's label — mirrors the
  # priority order project_plan.md asks for, adapted to what this app can
  # actually derive today (see OperatorPathResolver): a route-line comment is
  # the strongest signal, a bare controller/action identity the weakest.
  # i18n_derived/view_text_derived are reserved for scanners not built yet —
  # keeping them in the enum now avoids a second migration when they land.
  def self.operator_path_source_enum
    {
      route_comment_derived: 0,
      i18n_derived: 1,
      view_text_derived: 2,
      crud_convention_derived: 3,
      controller_action_only: 4,
      manual: 5,
    }
  end
end
