module Projects
  class BuildBusinessModules < Actor
    include RepositoryPaths

    WORKTREE_NAME = "index"

    input :project
    output :parsed_routes
    output :resource_comments

    def call
      Repositories::RemoveWorktree.call(project: project, name: WORKTREE_NAME)
      Repositories::CreateWorktree.call(project: project, name: WORKTREE_NAME, ref: project.base_sha)
      worktree_path = worktree_dir_for(WORKTREE_NAME)

      parsed = parse_routes(worktree_path)
      self.parsed_routes = parsed[:routes]
      self.resource_comments = parsed[:resource_comments]

      # Updated in place by slug — past analyses' impact items and test cases
      # point at these modules' features, so a re-sync must not recreate
      # them (that silently dropped every historical link). Only modules
      # whose controller is gone from routes.rb are removed.
      Project.transaction do
        kept = parsed_routes.map(&:controller).uniq.map { |controller| upsert_module(controller) }
        project.business_modules.where.not(id: kept.map(&:id)).destroy_all
      end
    rescue StandardError => e
      fail_with(I18n.t("actor.projects.build_business_modules.failed", message: e.message))
    ensure
      Repositories::RemoveWorktree.call(project: project, name: WORKTREE_NAME)
    end

    private

    def parse_routes(worktree_path)
      routes_path = File.join(worktree_path, "config", "routes.rb")
      return { routes: [], resource_comments: {} } unless File.exist?(routes_path)

      RoutesFileParser.call(routes_path: routes_path)
    end

    def upsert_module(controller)
      comment = resource_comments[controller]
      menu = comment.blank? && menu_label(controller)
      name = comment.presence&.delete_suffix("管理") || menu || humanize_controller(controller)
      source = comment.present? || menu ? "locale_derived" : "route_derived"

      project.business_modules.find_or_initialize_by(slug: controller.parameterize).tap do |mod|
        mod.update!(name: name, source: source)
      end
    end

    # With no Chinese routes.rb comment, the name operators actually see in
    # the app's own navbar (ScreenCatalog) — "庫存查詢" → "庫存" — beats a
    # humanized English controller name. Best effort: nil if the catalog
    # can't be built.
    def menu_label(controller)
      controller_path = controller.delete_suffix("Controller").underscore
      screens = screen_catalog&.all&.select { |s| s.controller_path == controller_path } || []
      label = ([ screen_catalog&.[]("#{controller_path}#index")&.menu_name ] + screens.map(&:menu_name))
                .compact.find { |name| name.match?(/\p{Han}/) }
      # "原料加工 工單列表" → "原料加工 工單": feature names add 列表/新增… themselves
      label&.sub(/\s*(?:管理|查詢|設定|列表)\z/, "")&.strip&.presence
    end

    def screen_catalog
      return @screen_catalog if defined?(@screen_catalog)

      @screen_catalog = ScreenCatalog.call(snapshot: RepositorySnapshot.new(git_dir: bare_repo_path, sha: project.base_sha))
    rescue StandardError => e
      Rails.logger.warn("[BuildBusinessModules:#{project.id}] screen catalog unavailable: #{e.message}")
      @screen_catalog = nil
    end

    # Includes the namespace, not just the controller's own name — real data
    # showed `Setting::BaseController`/`Estimate::BaseController`/
    # `Pms::BaseController` (none of which have a resources-line comment,
    # since they're plain `get "x", to: "x/base#index"` redirect routes, not
    # `resources`) would otherwise all humanize to the identical "Base" with
    # no way to tell them apart in the UI.
    def humanize_controller(controller)
      parts = controller.split("::")
      parts[-1] = parts[-1].delete_suffix("Controller")
      parts.map { |part| part.underscore.humanize }.join(" ")
    end

    def fail_with(message)
      project.update!(status: "failed", error_message: message)
      Rails.logger.error("[BuildBusinessModules:#{project.id}] #{message}")
      fail!(error: message)
    end
  end
end
