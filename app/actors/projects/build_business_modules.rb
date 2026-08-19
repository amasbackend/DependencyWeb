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

      Project.transaction do
        project.business_modules.destroy_all
        parsed_routes.map(&:controller).uniq.each { |controller| create_module(controller) }
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

    def create_module(controller)
      comment = resource_comments[controller]
      name = comment.presence&.delete_suffix("管理") || humanize_controller(controller)
      source = comment.present? ? "locale_derived" : "route_derived"

      project.business_modules.find_or_create_by!(slug: controller.parameterize) do |mod|
        mod.name = name
        mod.source = source
      end
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
