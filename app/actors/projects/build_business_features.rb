module Projects
  class BuildBusinessFeatures < Actor
    # Rule-derived sources (route/locale) map to FeatureCodeEntity's own
    # "rule_based" — the two models use different source vocabularies
    # (BusinessModule/BusinessFeature distinguish *where* the Chinese label
    # came from; FeatureCodeEntity only cares whether the *link* was rule- or
    # LLM-derived), so this bridges them rather than conflating the two enums.
    FEATURE_CODE_ENTITY_SOURCE = {
      "locale_derived" => "rule_based",
      "route_derived" => "rule_based",
      "llm_inferred" => "llm_inferred",
    }.freeze

    input :project
    input :parsed_routes
    output :business_features_count

    def call
      # In place by (module, slug), like Projects::BuildBusinessModules — only
      # features no longer backed by a route are removed.
      Project.transaction do
        kept = parsed_routes.group_by(&:controller).flat_map { |controller, routes| build_for_controller(controller, routes) }
        BusinessFeature.where(business_module: project.business_modules).where.not(id: kept.compact.map(&:id)).destroy_all
      end

      self.business_features_count = project.business_features.count
      resolve_operator_paths
      project.update!(
        status: "ready", analysis_status: "completed",
        last_synced_at: Time.current, last_synced_sha: project.base_sha,
      )
    rescue StandardError => e
      fail_with(I18n.t("actor.projects.build_business_features.failed", message: e.message))
    end

    private

    def build_for_controller(controller, routes)
      business_module = project.business_modules.find_by(slug: controller.parameterize)
      return [] unless business_module

      routes.map { |route| build_feature(business_module, route) }
    end

    def build_feature(business_module, route)
      naming = BusinessFeatureNamer.call(route: route, resource_label: business_module.name)
      naming = previous_llm_name(business_module, route) || infer_via_llm(route, business_module.name) if naming.needs_llm
      return unless naming

      feature = business_module.business_features.find_or_initialize_by(slug: naming.slug)
      feature.update!(project: project, name: naming.name, domain_action: route.action, source: naming.source)

      link_code_entity(feature, route, naming.source)
      feature
    end

    # A name the LLM already gave this action on an earlier sync — reused so
    # re-syncing doesn't pay for (or reword) the same names again.
    def previous_llm_name(business_module, route)
      existing = business_module.business_features.find_by(slug: route.action)
      return unless existing && existing.source.to_s == "llm_inferred"

      BusinessFeatureNamer::Result.new(slug: route.action, name: existing.name, source: "llm_inferred", needs_llm: false)
    end

    def link_code_entity(feature, route, source)
      code_entity = project.code_entities.find_by(
        entity_type: "controller", class_name: route.controller, method_name: route.action
      )
      return unless code_entity

      FeatureCodeEntity.find_or_create_by!(business_feature: feature, code_entity: code_entity) do |fce|
        fce.role = "controller_action"
        fce.source = FEATURE_CODE_ENTITY_SOURCE.fetch(source, "manual")
      end
    end

    # Runs once per build/re-sync (not per request — see OperatorPathResolver)
    # so Operator Path is already computed and cached by the time any page
    # renders it. Preloads what the resolver reads per-feature so this stays
    # O(1) queries regardless of feature count, not O(n).
    def resolve_operator_paths
      project.business_features.includes(:business_module, feature_code_entities: :code_entity).find_each do |feature|
        OperatorPathResolver.call(feature: feature)
      end
    end

    def infer_via_llm(route, resource_label)
      response = Llm::Provider.current.generate(system: llm_system_prompt, prompt: llm_prompt(route, resource_label), json: true)
      data = response.parsed_json
      BusinessFeatureNamer::Result.new(slug: route.action, name: data.fetch("name"), source: "llm_inferred", needs_llm: false)
    rescue StandardError => e
      Rails.logger.error("[BuildBusinessFeatures:#{project.id}] LLM inference failed for #{route.controller}##{route.action}: #{e.message}")
      nil
    end

    def llm_system_prompt
      "You map Rails controller actions in a Traditional Chinese ERP system to short, human-facing business feature " \
        "names, in the same style as existing ones (e.g. 新增使用者, 編輯客戶). Respond only with the feature name " \
        "grounded in the given controller/action/resource — never invent a workflow you weren't given evidence for."
    end

    def llm_prompt(route, resource_label)
      <<~PROMPT
        Controller: #{route.controller}
        Action: #{route.action}
        Resource: #{resource_label}
        請用繁體中文為這個操作命名一個簡短的業務功能名稱，並以 JSON 回覆：{"name": "..."}
      PROMPT
    end

    def fail_with(message)
      project.update!(status: "failed", error_message: message)
      Rails.logger.error("[BuildBusinessFeatures:#{project.id}] #{message}")
      fail!(error: message)
    end
  end
end
