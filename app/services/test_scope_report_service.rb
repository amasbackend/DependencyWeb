# frozen_string_literal: true

class TestScopeReportService
  MUST_TEST_LEVELS = %w[direct callee].freeze
  SUGGESTED_LEVELS = %w[caller caller_l2 model_consumer concern].freeze

  # 預設操作步驟／預期結果（CRUD + 常見行為）
  DEFAULT_OPERATION_PLAYBOOK = {
    "新增" => {
      steps: "1. 開啟新增頁；2. 填入必填欄位；3. 送出；4. 回列表／詳情確認新資料",
      expected: "建立成功，資料正確寫入且畫面顯示一致",
    },
    "列表" => {
      steps: "1. 開啟列表頁；2. 確認資料列顯示；3. 執行搜尋／篩選（若有）",
      expected: "列表資料正確，搜尋／篩選結果符合條件",
    },
    "檢視" => {
      steps: "1. 自列表進入詳情／檢視；2. 核對主要欄位與關聯資料",
      expected: "詳情內容正確、無缺漏欄位",
    },
    "編輯" => {
      steps: "1. 開啟編輯頁；2. 修改目標欄位；3. 送出；4. 重新開啟確認變更",
      expected: "更新成功，變更持久化且畫面反映正確",
    },
    "刪除" => {
      steps: "1. 執行刪除；2. 確認確認框（若有）；3. 回列表確認資料消失或狀態變更",
      expected: "刪除成功，列表不再顯示該筆（或狀態正確）",
    },
    "封存" => {
      steps: "1. 執行封存；2. 確認狀態變更；3. 以篩選確認封存資料行為",
      expected: "狀態改為封存，後續流程符合權限／可見性規則",
    },
    "匯入" => {
      steps: "1. 準備合法匯入檔；2. 上傳並匯入；3. 確認成功筆數與抽樣資料",
      expected: "匯入成功，資料正確寫入；錯誤列有明確訊息",
    },
    "匯出" => {
      steps: "1. 觸發匯出；2. 下載檔案；3. 抽樣核對內容",
      expected: "檔案可下載且欄位／數值正確",
    },
    "定稿" => {
      steps: "1. 確認前置狀態；2. 執行定稿；3. 確認狀態與後續可編輯性",
      expected: "定稿成功，狀態與限制符合規格",
    },
    "成交" => {
      steps: "1. 填寫成交必要資訊；2. 送出成交；3. 確認訂單／狀態產生",
      expected: "成交成功，關聯訂單／狀態正確",
    },
    "開始" => {
      steps: "1. 確認前置條件；2. 執行開始；3. 確認狀態與時間欄位",
      expected: "開始成功，狀態與時間正確",
    },
    "結束" => {
      steps: "1. 執行結束；2. 確認狀態／產量等欄位；3. 確認後續不可再開始（若有）",
      expected: "結束成功，狀態與結算資料正確",
    },
    "排程" => {
      steps: "1. 開啟排程畫面；2. 調整排程；3. 儲存並重新載入確認",
      expected: "排程更新成功，畫面與資料一致",
    },
    "匯入圖面" => {
      steps: "1. 上傳圖面；2. 確認上傳結果；3. 重新開啟檢視圖面",
      expected: "圖面可預覽／下載且關聯正確",
    },
  }.freeze

  API_PLAYBOOK = {
    steps: "1. 以具備權限帳號呼叫 API；2. 確認 HTTP status；3. 核對 response body 與資料庫副作用",
    expected: "API 回傳正確 status／payload，資料異動符合預期",
  }.freeze

  GENERIC_PLAYBOOK = {
    steps: "1. 依功能路徑進入操作；2. 執行主要動作；3. 確認畫面與資料結果",
    expected: "操作成功，無未處理錯誤，資料與畫面一致",
  }.freeze

  def generate(company:, pr_number:, format: "qa", pr_summary: nil)
    impacts = ImpactRecord.for_pr(company.id, pr_number).to_a
    entry_points_by_action = EntryPoint.where(company: company).includes(:ui_menu).index_by(&:action_page_id)
    ui_menus_by_controller = company.ui_menus.group_by(&:controller_path)
    action_pages = company.action_pages.includes(:management_page, :relate_models).index_by(&:id)

    qa_body = build_qa_report(
      company, pr_number, impacts, action_pages, entry_points_by_action, ui_menus_by_controller, pr_summary
    )
    tech_body = build_tech_report(company, pr_number, impacts, action_pages)

    case format.to_s
    when "tech"
      tech_body
    when "both"
      { qa: qa_body, tech: tech_body }
    else
      qa_body
    end
  end

  def to_markdown(report)
    lines = [
      "# PR ##{report[:pr_number]} 手動迴歸測試清單",
      "",
      "專案：#{report[:company]}",
    ]

    if report[:pr_title].present?
      lines << "PR 標題：#{report[:pr_title]}"
    end
    if report[:pr_url].present?
      lines << "PR 連結：#{report[:pr_url]}"
    end
    lines << ""

    lines.concat(markdown_summary_section(report))
    lines.concat(markdown_table_section("必測項目", report[:must_test]))
    lines.concat(markdown_table_section("建議迴歸", report[:suggested_regression]))

    if report[:column_impacts]&.any?
      lines << "## 資料庫欄位異動"
      lines << ""
      lines << "| 資料表 | 欄位 | 變更類型 |"
      lines << "|--------|------|----------|"
      report[:column_impacts].each do |col|
        lines << "| #{md_cell(col['table'] || col[:table])} | #{md_cell(col['column'] || col[:column])} | #{md_cell(col['change_type'] || col[:change_type])} |"
      end
      lines << ""
    end

    if report[:uncovered_risks]&.any?
      lines << "## 未覆蓋風險"
      report[:uncovered_risks].each { |risk| lines << "- #{risk}" }
      lines << ""
    end

    if report[:no_spec_coverage]&.any?
      lines << "## 無 Spec 覆蓋"
      report[:no_spec_coverage].each { |name| lines << "- #{name}" }
      lines << ""
    end

    lines.join("\n")
  end

  private

  def build_qa_report(company, pr_number, impacts, action_pages, entry_points_by_action, ui_menus_by_controller, pr_summary)
    must_test = []
    suggested_regression = []
    seen_actions = {}

    impacts.each do |impact|
      next unless impact.target_type == "action_page"

      action_page = action_pages[impact.target_id]
      next unless action_page
      next if seen_actions[action_page.id]

      seen_actions[action_page.id] = true
      entry = entry_points_by_action[action_page.id]
      item = build_qa_item(company, action_page, entry, impact, entry_points_by_action, ui_menus_by_controller)

      if MUST_TEST_LEVELS.include?(impact.impact_level)
        must_test << item
      elsif SUGGESTED_LEVELS.include?(impact.impact_level)
        suggested_regression << item
      end
    end

    analysis = PrAnalysis.for_pr(company.id, pr_number).first
    column_impacts = analysis&.analysis_input&.dig("column_impacts") || []
    uncovered_risks = build_uncovered_risks(analysis&.analysis_input)
    no_spec_coverage = build_no_spec_coverage(company, must_test, suggested_regression)
    summary_meta = normalize_pr_summary(pr_summary)

    {
      pr_number: pr_number,
      company: company.name,
      view: "qa",
      pr_title: summary_meta[:title],
      pr_url: summary_meta[:html_url],
      pr_body: summary_meta[:body],
      summary: {
        must_test: must_test.size,
        suggested_regression: suggested_regression.size,
        no_spec_coverage: no_spec_coverage.size,
      },
      must_test: must_test,
      suggested_regression: suggested_regression,
      column_impacts: column_impacts,
      uncovered_risks: uncovered_risks,
      no_spec_coverage: no_spec_coverage,
    }
  end

  def build_tech_report(company, pr_number, impacts, action_pages)
    {
      pr_number: pr_number,
      company: company.name,
      view: "tech",
      impacts: impacts.map do |impact|
        target_name = resolve_target_name(impact, action_pages)
        {
          source_type: impact.source_type,
          source_name: impact.source_name,
          source_file_path: impact.source_file_path,
          target_type: impact.target_type,
          target_id: impact.target_id,
          target_name: target_name,
          impact_level: impact.impact_level,
          reason: impact.reason,
        }
      end,
    }
  end

  def build_qa_item(company, action_page, entry, impact, entry_points_by_action, ui_menus_by_controller)
    model_hint = Array(action_page.relate_model).first
    affected_columns = Array(action_page.modify_column).presence ||
                       Array(action_page.select_column).presence ||
                       []
    menu_path = menu_path_for(company, action_page, entry, entry_points_by_action, ui_menus_by_controller)
    operation = operation_label(company, action_page)
    route = route_hint(entry)
    playbook = playbook_for(operation, entry)

    {
      menu_path: menu_path,
      operation: operation,
      action_page: action_page.name,
      perm: permission_label(company, entry),
      affected_fields: column_labels(company, model_hint, affected_columns),
      entry_url: entry&.route_path,
      route_hint: route,
      test_step: test_step_label(menu_path, operation, route),
      operation_steps: playbook[:steps],
      expected_result: playbook[:expected],
      channel: entry&.channel || action_page.channel || "web",
      impact_level: impact.impact_level,
      reason: impact.reason,
    }
  end

  def test_step_label(menu_path, operation, route)
    path_part = [menu_path.presence, operation.presence].compact.join(" > ")
    return path_part if route.blank? || route == "—"

    "#{path_part} (#{route})"
  end

  def route_hint(entry)
    return "—" unless entry&.controller_path.present?

    path = entry.controller_path.to_s
    action = entry.controller_action.to_s
    suffix, default_method = rails_rest_hint(action)
    method = entry.http_method.presence || default_method
    prefix = entry.channel == "api" ? "API " : ""

    "#{prefix}#{path}#{suffix} #{method}".strip
  end

  # 對齊手動清單慣例：create 顯示為 .../new post（如 setting/components/new post）
  def rails_rest_hint(action)
    case action.to_s
    when "index", "list"
      ["", "get"]
    when "new"
      ["/new", "get"]
    when "create"
      ["/new", "post"]
    when "show", "info", "find"
      ["/:id", "get"]
    when "edit"
      ["/:id/edit", "get"]
    when "update"
      ["/:id", "patch"]
    when "destroy", "delete"
      ["/:id", "delete"]
    when "archive"
      ["/:id", "patch"]
    when "start", "stop", "finalize", "sold", "copy", "update_schedule", "per_produce_time", "processing_time"
      ["/:id/#{action}", default_member_method(action)]
    else
      ["/#{action}", default_collection_method(action)]
    end
  end

  def default_member_method(action)
    case action.to_s
    when "start", "stop", "update_schedule" then "patch"
    when "finalize", "sold" then "post"
    when "copy", "per_produce_time", "processing_time" then "get"
    else "post"
    end
  end

  def default_collection_method(action)
    case action.to_s
    when /\A(create|import|accident)/ then "post"
    when /\A(update|start|stop|recover)/ then "patch"
    else "get"
    end
  end

  def playbook_for(operation, entry)
    if entry&.channel == "api"
      return API_PLAYBOOK
    end

    DEFAULT_OPERATION_PLAYBOOK[operation].presence || GENERIC_PLAYBOOK
  end

  def menu_path_for(company, action_page, entry, _entry_points_by_action, ui_menus_by_controller)
    if entry&.ui_menu
      menu = entry.ui_menu
      module_part = menu.module_label.presence || menu.namespace.presence
      return [module_part, menu.menu_label].compact.join(" > ")
    end

    if entry&.controller_path.present?
      menu = ui_menus_by_controller[entry.controller_path]&.first
      if menu
        module_part = menu.module_label.presence || menu.namespace.presence
        return [module_part, menu.menu_label].compact.join(" > ")
      end
    end

    management_page_label(company, action_page.management_page)
  end

  def management_page_label(company, management_page)
    return nil unless management_page

    name = management_page.name.to_s
    lm = company.locale_metadata
    lm&.menu_labels&.[](name).presence ||
      lm&.model_labels&.[](name).presence ||
      lm&.perm_module_labels&.[](name).presence ||
      name
  end

  def operation_label(company, action_page)
    labels = company.locale_metadata&.operation_type_labels || {}
    key = action_page.name.to_s.split("::").last&.underscore
    inferred = OperationTypeInfererService.infer(action_page.name, labels: labels)
    stored = action_page.operation_type.presence
    suffix = action_page.name.to_s.split("::").last
    return inferred if key.present? && labels[key].present?
    return inferred if stored.blank? || stored == suffix

    stored
  end

  def permission_label(company, entry)
    return nil unless entry&.perm_module.present?

    lm = company.locale_metadata
    module_label = lm&.perm_module_labels&.[](entry.perm_module).presence || entry.perm_module
    action_label =
      if entry.perm_action.present?
        lm&.perm_action_labels&.[](entry.perm_action).presence || entry.perm_action
      end

    [module_label, action_label].compact.join(" / ")
  end

  def column_labels(company, model_hint, columns)
    return [] if columns.blank?

    attribute_labels = company.locale_metadata&.attribute_labels || {}
    model_key = model_hint.to_s.underscore
    model_attrs = attribute_labels[model_key] || {}

    Array(columns).map do |col|
      col_key = col.to_s
      model_attrs[col_key] ||
        model_attrs[col_key.underscore] ||
        cross_model_attribute_label(attribute_labels, col_key) ||
        col_key
    end
  end

  def cross_model_attribute_label(attribute_labels, col_key)
    attribute_labels.each_value do |attrs|
      next unless attrs.is_a?(Hash)

      label = attrs[col_key] || attrs[col_key.underscore]
      return label if label.present?
    end
    nil
  end

  def resolve_target_name(impact, action_pages)
    case impact.target_type
    when "action_page"
      action_pages[impact.target_id]&.name
    when "relate_model"
      RelateModel.find_by(id: impact.target_id)&.name
    when "entry_point"
      EntryPoint.find_by(id: impact.target_id)&.controller_path
    end
  end

  def build_uncovered_risks(analysis_input)
    return [] unless analysis_input

    risks = []
    route_count = analysis_input.dig("classified_counts", "route").to_i
    risks << "routes.rb 有變更，請手動確認新增/修改的路由" if route_count.positive?
    risks
  end

  def build_no_spec_coverage(company, must_test, suggested_regression)
    names = (must_test + suggested_regression).pluck(:action_page).uniq
    action_pages = company.action_pages.where(name: names).index_by(&:name)

    names.filter_map do |name|
      page = action_pages[name]
      name if page && !page.has_spec
    end
  end

  def normalize_pr_summary(pr_summary)
    return { title: nil, body: nil, html_url: nil } if pr_summary.blank?

    data = pr_summary.respond_to?(:with_indifferent_access) ? pr_summary.with_indifferent_access : pr_summary
    {
      title: data[:title].presence,
      body: data[:body].presence || data[:commented].presence || data[:comment].presence,
      html_url: data[:html_url].presence || data[:url].presence,
    }
  end

  def markdown_summary_section(report)
    lines = ["## 修改摘要", ""]
    body = report[:pr_body].to_s.strip
    if body.present?
      lines << body
    else
      lines << "_（PR 描述／comment 為空，請手動補上修改摘要）_"
    end
    lines << ""
    lines << "- 必測：#{report.dig(:summary, :must_test) || 0}"
    lines << "- 建議迴歸：#{report.dig(:summary, :suggested_regression) || 0}"
    lines << ""
    lines
  end

  def markdown_table_section(title, items)
    lines = ["## #{title}", ""]
    if items.blank?
      lines << "_無_"
      lines << ""
      return lines
    end

    lines << "| # | 測試步驟 | 操作步驟 | 預期結果 | 權限 | Actor |"
    lines << "|---|----------|----------|----------|------|-------|"
    items.each_with_index do |item, index|
      lines << "| #{index + 1} | #{md_cell(item[:test_step])} | #{md_cell(item[:operation_steps])} | #{md_cell(item[:expected_result])} | #{md_cell(item[:perm] || '—')} | #{md_cell(item[:action_page])} |"
    end
    lines << ""
    lines
  end

  def md_cell(value)
    value.to_s.gsub("|", "\\|").gsub(/\r?\n/, "<br>").presence || "—"
  end
end
