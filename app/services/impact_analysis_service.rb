# frozen_string_literal: true

class ImpactAnalysisService
  IMPACT_PRIORITY = {
    "direct" => 5,
    "caller" => 4,
    "callee" => 3,
    "model_consumer" => 2,
    "concern" => 2,
    "caller_l2" => 1,
  }.freeze

  def analyze(company:, pr_number:, actor_changes:, model_changes:, controller_changes: [], migration_changes: [],
              concern_changes: [], blueprint_changes: [])
    graph = DependencyGraphService.new(company)
    impacts = {}

    actor_changes.each do |change|
      apply_actor_change!(impacts, graph, change, pr_number)
    end

    model_changes.each do |change|
      apply_model_change!(impacts, graph, change, pr_number)
    end

    controller_changes.each do |change|
      apply_controller_change!(impacts, company, change)
    end

    migration_changes.each do |change|
      apply_migration_change!(impacts, graph, change)
    end

    concern_changes.each do |change|
      apply_concern_change!(impacts, company, change)
    end

    blueprint_changes.each do |change|
      apply_blueprint_change!(impacts, company, change)
    end

    impacts.values
  end

  def analyze_and_persist!(company:, pr_number:, actor_changes:, model_changes:, controller_changes: [], migration_changes: [],
                           concern_changes: [], blueprint_changes: [])
    impacts = analyze(
      company: company,
      pr_number: pr_number,
      actor_changes: actor_changes,
      model_changes: model_changes,
      controller_changes: controller_changes,
      migration_changes: migration_changes,
      concern_changes: concern_changes,
      blueprint_changes: blueprint_changes,
    )

    ImpactRecord.transaction do
      impacts.each do |attrs|
        ImpactRecord.create!(attrs.merge(company_id: company.id, pr_number: pr_number))
      end
      sync_changed_flags!(impacts)
    end

    build_summary(
      impacts,
      actor_changes,
      model_changes,
      controller_changes: controller_changes,
      migration_changes: migration_changes,
      concern_changes: concern_changes,
      blueprint_changes: blueprint_changes,
    )
  end

  private

  def apply_actor_change!(impacts, graph, change, pr_number)
    actor_name = change[:actor_name]
    file_path = change[:file_path]
    source = source_attrs("actor", actor_name, file_path)

    action_page = graph.action_pages_by_name[actor_name]
    if action_page
      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "direct",
          reason: "PR 直接修改 Actor #{actor_name}",
          metadata: { management_page: action_page.management_page&.name },
        ),
      )

      action_page.relate_models.each do |relate_model|
        merge_impact!(
          impacts,
          build_impact(
            source: source,
            target_type: "relate_model",
            target_id: relate_model.id,
            impact_level: "callee",
            reason: "直接變更的 Actor #{actor_name} 使用 Model #{relate_model.name}",
            metadata: {
              action_page: action_page.name,
              management_page: action_page.management_page&.name,
            },
          ),
        )
      end
    end

    graph.callers_of_actor(actor_name, max_depth: 2).each do |caller_page, depth|
      level = depth == 1 ? "caller" : "caller_l2"
      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "action_page",
          target_id: caller_page.id,
          impact_level: level,
          reason: "#{level == 'caller' ? '一層' : '二層'}呼叫鏈：#{caller_page.name} 關聯已變更的 #{actor_name}",
          metadata: { management_page: caller_page.management_page&.name },
        ),
      )
    end
  end

  def apply_model_change!(impacts, graph, change, _pr_number)
    model_name = change[:model_name]
    file_path = change[:file_path]
    source = source_attrs("model", model_name, file_path)

    (graph.model_consumers_of[model_name] || []).each do |action_page|
      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "model_consumer",
          reason: "Action #{action_page.name} 使用已變更的 Model #{model_name}",
          metadata: { management_page: action_page.management_page&.name },
        ),
      )
    end

    (graph.relate_models_by_name[model_name] || []).each do |relate_model|
      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "relate_model",
          target_id: relate_model.id,
          impact_level: "direct",
          reason: "PR 直接修改 Model #{model_name}",
          metadata: {
            action_page: relate_model.action_page&.name,
            management_page: relate_model.management_page&.name,
          },
        ),
      )
    end
  end

  def apply_controller_change!(impacts, company, change)
    controller_path = change[:controller_path]
    file_path = change[:file_path]
    source = source_attrs("controller", controller_path, file_path)

    EntryPoint.where(company: company, controller_path: controller_path).find_each do |entry|
      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "entry_point",
          target_id: entry.id,
          impact_level: "direct",
          reason: "PR 修改 Controller #{controller_path}##{entry.controller_action}",
          metadata: { route_path: entry.route_path },
        ),
      )

      next unless entry.action_page_id

      action_page = entry.action_page
      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "direct",
          reason: "Controller #{controller_path} 對應 Actor #{action_page.name}",
          metadata: { management_page: action_page.management_page&.name },
        ),
      )
    end
  end

  def apply_migration_change!(impacts, graph, change)
    file_path = change[:file_path]
    source_name = File.basename(file_path, ".rb")
    source = source_attrs("migration", source_name, file_path)

    Array(change[:column_impacts]).each do |col|
      model_name = col[:model_name]
      column = col[:column]

      (graph.model_consumers_of[model_name] || []).each do |action_page|
        next unless column_referenced?(action_page, column)

        merge_impact!(
          impacts,
          build_impact(
            source: source,
            target_type: "action_page",
            target_id: action_page.id,
            impact_level: "model_consumer",
            reason: "Migration #{col[:change_type]} #{col[:table]}.#{column} 影響使用欄位的 #{action_page.name}",
            metadata: {
              management_page: action_page.management_page&.name,
              column: column,
              change_type: col[:change_type],
            },
          ),
        )
      end

      (graph.relate_models_by_name[model_name] || []).each do |relate_model|
        merge_impact!(
          impacts,
          build_impact(
            source: source,
            target_type: "relate_model",
            target_id: relate_model.id,
            impact_level: "direct",
            reason: "Migration #{col[:change_type]} 影響 Model #{model_name}",
            metadata: {
              column: column,
              change_type: col[:change_type],
            },
          ),
        )
      end
    end
  end

  def apply_concern_change!(impacts, company, change)
    concern_name = change[:concern_name]
    file_path = change[:file_path]
    source = source_attrs("concern", concern_name, file_path)

    SharedConcern.where(company: company, concern_name: concern_name).includes(:action_page).find_each do |shared|
      action_page = shared.action_page
      next unless action_page

      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "concern",
          reason: "PR 修改 Concern #{concern_name}，#{action_page.name} 有 include",
          metadata: { management_page: action_page.management_page&.name },
        ),
      )
    end
  end

  def apply_blueprint_change!(impacts, company, change)
    blueprint_name = change[:blueprint_name]
    file_path = change[:file_path]
    source = source_attrs("blueprint", blueprint_name, file_path)

    ActionPage.where(company: company).find_each do |action_page|
      next unless Array(action_page.blueprint_names).include?(blueprint_name)

      merge_impact!(
        impacts,
        build_impact(
          source: source,
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "model_consumer",
          reason: "PR 修改 Blueprint #{blueprint_name}，#{action_page.name} 有引用",
          metadata: { management_page: action_page.management_page&.name },
        ),
      )
    end
  end

  def column_referenced?(action_page, column)
    cols = [
      *Array(action_page.select_column),
      *Array(action_page.modify_column),
      *Array(action_page.delete_column),
    ].map(&:to_s)

    cols.any? { |c| c == column.to_s || c.underscore == column.to_s }
  end

  def source_attrs(source_type, source_name, file_path)
    { source_type: source_type, source_name: source_name, source_file_path: file_path }
  end

  def build_impact(source:, target_type:, target_id:, impact_level:, reason:, metadata: {})
    source.merge(
      target_type: target_type,
      target_id: target_id,
      impact_level: impact_level,
      reason: reason,
      metadata: metadata,
    )
  end

  def normalize_impacts(impacts)
    impacts.is_a?(Hash) ? impacts.values : impacts
  end

  def impact_key(impact)
    [impact[:target_type], impact[:target_id]]
  end

  def merge_impact!(impacts, new_impact)
    key = impact_key(new_impact)
    existing = impacts[key]

    if existing.nil? || IMPACT_PRIORITY.fetch(new_impact[:impact_level], 0) > IMPACT_PRIORITY.fetch(existing[:impact_level], 0)
      impacts[key] = new_impact
    end
  end

  def sync_changed_flags!(impacts)
    list = normalize_impacts(impacts)
    action_page_ids = list.select { |i| i[:target_type] == "action_page" }.pluck(:target_id).uniq
    relate_model_ids = list.select { |i| i[:target_type] == "relate_model" }.pluck(:target_id).uniq

    ActionPage.where(id: action_page_ids).update_all(changed_flag: true) if action_page_ids.any?
    RelateModel.where(id: relate_model_ids).update_all(changed_flag: true) if relate_model_ids.any?
  end

  def build_summary(impacts, actor_changes, model_changes, controller_changes: [], migration_changes: [],
                    concern_changes: [], blueprint_changes: [])
    list = normalize_impacts(impacts)
    grouped = list.group_by { |i| i[:impact_level] }
    action_page_ids = list.select { |i| i[:target_type] == "action_page" }.pluck(:target_id).uniq
    relate_model_ids = list.select { |i| i[:target_type] == "relate_model" }.pluck(:target_id).uniq

    {
      changed_files_count: nil,
      direct_actors: actor_changes.map { |c| c[:actor_name] },
      direct_models: model_changes.map { |c| c[:model_name] },
      direct_controllers: controller_changes.map { |c| c[:controller_path] },
      migration_files: migration_changes.map { |c| c[:file_path] },
      direct_concerns: concern_changes.map { |c| c[:concern_name] },
      direct_blueprints: blueprint_changes.map { |c| c[:blueprint_name] },
      total_impacts: list.size,
      action_pages_flagged: action_page_ids.size,
      relate_models_flagged: relate_model_ids.size,
      by_level: ImpactRecord::IMPACT_LEVELS.index_with { |level| (grouped[level] || []).size },
    }
  end
end
