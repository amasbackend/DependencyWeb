# frozen_string_literal: true

class ExtendedRelationService
  def initialize(github_service: GithubRepoService.new)
    @github = github_service
    @spec_scanner = SpecScannerService.new(github_service: github_service)
    @pack_scanner = FrontendPackScannerService.new(github_service: github_service)
    @warnings = []
  end

  attr_reader :warnings

  def enrich!(company:, owner:, repo:, branch:)
    spec_actors = @spec_scanner.actor_names_with_specs(owner: owner, repo: repo, branch: branch)
    packs_by_controller = @pack_scanner.packs_by_controller_path(owner: owner, repo: repo, branch: branch)

    company.action_pages.find_each do |action_page|
      action_page.update!(has_spec: spec_actors.include?(action_page.name))
      attach_related_files!(company, action_page, packs_by_controller)
    end

    link_route_entry_types!(company, owner, repo, branch)

    {
      specs_matched: company.action_pages.where(has_spec: true).count,
      shared_concerns: company.shared_concerns.count,
      warnings: @warnings,
    }
  rescue StandardError => e
    @warnings << "Extended relations 匯入失敗: #{e.message}"
    { specs_matched: 0, shared_concerns: company.shared_concerns.count, warnings: @warnings }
  end

  private

  def attach_related_files!(company, action_page, packs_by_controller)
    controller_paths = company.entry_points.where(action_page: action_page).pluck(:controller_path).compact.uniq
    related = controller_paths.flat_map { |path| packs_by_controller[path] || [] }.uniq
    return if related.blank?

    action_page.update!(related_files: related)
  end

  def link_route_entry_types!(company, owner, repo, branch)
    routes_file = @github.get_file_content(owner, repo, "config/routes.rb", branch)
    return unless routes_file

    route_parser = RouteParserService.new
    routes = route_parser.parse(routes_file[:content])

    company.entry_points.find_each do |entry|
      entry_type = route_parser.entry_type_for_controller_action(
        routes,
        entry.controller_path,
        entry.controller_action,
      )
      entry.update!(entry_type: entry_type) if entry_type != entry.entry_type
    end
  rescue StandardError => e
    @warnings << "Route entry_type 標記失敗: #{e.message}"
  end
end
