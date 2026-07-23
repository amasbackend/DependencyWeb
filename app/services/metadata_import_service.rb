# frozen_string_literal: true

class MetadataImportService
  LOCALE_PATHS = [
    "config/locales/zh-TW/model.yml",
    "config/locales/zh-TW.yml",
  ].freeze

  def initialize(github_service: GithubRepoService.new)
    @github = github_service
    @warnings = []
  end

  attr_reader :warnings

  # best-effort：失敗時記錄 warning，不拋出例外阻斷主匯入
  def import!(company:, owner:, repo:, branch:)
    clear_metadata!(company)

    locale_record = import_locale_metadata!(company, owner, repo, branch)
    ui_menus = import_ui_menus!(company, owner, repo, branch, locale_record)
    routes = import_routes(owner, repo, branch)
    import_entry_points!(company, owner, repo, branch, ui_menus, routes)
    enrich_action_pages!(company, locale_record)

    {
      ui_menus: company.ui_menus.count,
      entry_points: company.entry_points.count,
      locale: locale_record.present?,
      warnings: @warnings,
    }
  rescue StandardError => e
    @warnings << "Metadata 匯入中斷: #{e.message}"
    puts "⚠️  #{@warnings.last}"
    { ui_menus: 0, entry_points: 0, locale: false, warnings: @warnings }
  end

  private

  def clear_metadata!(company)
    company.entry_points.destroy_all
    company.ui_menus.destroy_all
    company.locale_metadata&.destroy
  end

  def import_locale_metadata!(company, owner, repo, branch)
    content = fetch_first_file(owner, repo, branch, LOCALE_PATHS)
    return nil if content.blank?

    parsed = LocaleParserService.new.parse(content)
    LocaleMetadata.create!(
      company: company,
      locale: "zh-TW",
      model_labels: parsed[:model_labels],
      attribute_labels: parsed[:attribute_labels],
      perm_module_labels: parsed[:perm_module_labels],
      perm_action_labels: parsed[:perm_action_labels],
      operation_type_labels: parsed[:operation_type_labels],
      menu_labels: parsed[:menu_labels],
      state_labels: parsed[:state_labels],
      imported_at: Time.current,
    )
  rescue StandardError => e
    @warnings << "Locale 匯入失敗: #{e.message}"
    nil
  end

  def import_ui_menus!(company, owner, repo, branch, locale_record)
    created = []

    navbar_files = @github.get_directory_files(owner, repo, "app/views", branch)
                          .select { |f| f[:path].include?("_navbar") }

    perm_labels = locale_record&.perm_module_labels || {}

    navbar_files.each do |file_info|
      file = @github.get_file_content(owner, repo, file_info[:path], branch)
      next unless file

      NavbarParserService.new.parse(file[:content], source_path: file_info[:path]).each do |menu|
        module_label = perm_labels[menu[:perm_module]] if menu[:perm_module].present?
        created << company.ui_menus.create!(
          namespace: menu[:namespace],
          menu_label: menu[:menu_label],
          module_label: module_label,
          controller_path: menu[:controller_path],
          actions: menu[:actions],
          perm_module: menu[:perm_module],
        )
      end
    end

    created
  rescue StandardError => e
    @warnings << "Navbar 匯入失敗: #{e.message}"
    created
  end

  def import_routes(owner, repo, branch)
    file = @github.get_file_content(owner, repo, "config/routes.rb", branch)
    return [] unless file

    RouteParserService.new.parse(file[:content])
  rescue StandardError => e
    @warnings << "Routes 匯入失敗: #{e.message}"
    []
  end

  def import_entry_points!(company, owner, repo, branch, ui_menus, routes)
    action_pages_by_name = company.action_pages.index_by(&:name)
    menus_by_controller = ui_menus.group_by(&:controller_path)
    parser = ControllerActorParserService.new
    route_parser = RouteParserService.new

    controller_files = @github.get_directory_files(owner, repo, "app/controllers", branch)
                              .select { |f| f[:path].end_with?("_controller.rb") }

    controller_files.each do |file_info|
      file = @github.get_file_content(owner, repo, file_info[:path], branch)
      next unless file

      parser.parse_file(file[:content], file_path: file_info[:path]).each do |entry|
        action_page = action_pages_by_name[entry[:actor_name]]
        ui_menu = (menus_by_controller[entry[:controller_path]] || []).first

        route_comment = route_parser.comment_for_controller_action(
          routes,
          entry[:controller_path],
          entry[:controller_action],
        )

        company.entry_points.create!(
          action_page: action_page,
          ui_menu: ui_menu,
          controller_path: entry[:controller_path],
          controller_action: entry[:controller_action],
          route_comment: route_comment,
          perm_module: entry[:perm_module],
          perm_action: entry[:perm_action],
          channel: entry[:channel],
          entry_type: entry[:entry_type],
        )

        next unless action_page

        label = route_comment.presence || "#{entry[:controller_path]}##{entry[:controller_action]}"
        action_page.update!(
          display_label: label,
          channel: entry[:channel],
        )
      end
    end
  rescue StandardError => e
    @warnings << "EntryPoint 匯入失敗: #{e.message}"
  end

  def enrich_action_pages!(company, locale_record)
    op_labels = locale_record&.operation_type_labels || {}

    company.action_pages.find_each do |action_page|
      attrs = {
        operation_type: OperationTypeInfererService.infer(action_page.name, labels: op_labels),
      }
      attrs[:display_label] ||= action_page.name.split("::").last

      if action_page.source_file_path.present?
        # play_chain may already be set during code analysis import
        attrs[:play_chain] = action_page.play_chain if action_page.play_chain.blank?
      end

      action_page.update!(attrs)
    end
  rescue StandardError => e
    @warnings << "ActionPage 擴充失敗: #{e.message}"
  end

  def fetch_first_file(owner, repo, branch, paths)
    paths.each do |path|
      file = @github.get_file_content(owner, repo, path, branch)
      return file[:content] if file
    end
    nil
  end
end
