# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestScopeReportService do
  subject(:service) { described_class.new }

  let(:company) { Company.create!(name: "TestCo", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }
  let!(:ui_menu) do
    UiMenu.create!(
      company: company,
      namespace: "pms",
      menu_label: "工單管理",
      module_label: "生產管理",
      controller_path: "pms/work_orders",
      perm_module: "work_order",
    )
  end

  let!(:action_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Update",
      operation_type: "編輯",
      relate_model: ["WorkOrder"],
      modify_column: %w[estimated_hours],
      has_spec: false,
    )
  end

  let!(:entry_point) do
    EntryPoint.create!(
      company: company,
      action_page: action_page,
      ui_menu: ui_menu,
      controller_path: "pms/work_orders",
      controller_action: "update",
      perm_module: "work_order",
      perm_action: "edit",
      route_path: "/work_orders/:id/edit",
    )
  end

  let!(:locale_metadata) do
    LocaleMetadata.create!(
      company: company,
      model_labels: { "work_order" => "工單" },
      attribute_labels: { "work_order" => { "estimated_hours" => "預估工時" } },
      perm_module_labels: { "work_order" => "生產管理" },
      perm_action_labels: { "edit" => "編輯" },
      operation_type_labels: {},
      menu_labels: { "work_order" => "工單管理" },
      state_labels: {},
      imported_at: Time.current,
    )
  end

  before do
    ImpactRecord.create!(
      company: company,
      pr_number: 65,
      source_type: "actor",
      source_name: "WorkOrder::Update",
      source_file_path: "app/actors/work_order/update.rb",
      target_type: "action_page",
      target_id: action_page.id,
      impact_level: "direct",
      reason: "PR 直接修改 Actor WorkOrder::Update",
    )

    ImpactRecord.create!(
      company: company,
      pr_number: 65,
      source_type: "actor",
      source_name: "WorkOrder::Create",
      source_file_path: "app/actors/work_order/create.rb",
      target_type: "action_page",
      target_id: ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Create",
        operation_type: "新增",
        has_spec: true,
      ).id,
      impact_level: "caller",
      reason: "caller impact",
    )

    PrAnalysis.save_snapshot!(
      company: company,
      pr_number: 65,
      impact_summary: {},
      analysis_input: {
        column_impacts: [{ table: "work_orders", column: "estimated_hours", change_type: "add_column" }],
        classified_counts: { "route" => 1 },
      },
      qa_report: {},
      tech_report: {},
    )
  end

  it "builds QA report with menu path and operation" do
    report = service.generate(company: company, pr_number: 65, format: "qa")

    expect(report[:must_test].size).to eq(1)
    expect(report[:must_test].first[:action_page]).to eq("WorkOrder::Update")
    expect(report[:must_test].first[:operation]).to eq("編輯")
    expect(report[:must_test].first[:menu_path]).to eq("生產管理 > 工單管理")
    expect(report[:must_test].first[:perm]).to eq("生產管理 / 編輯")
    expect(report[:must_test].first[:affected_fields]).to include("預估工時")
    expect(report[:suggested_regression].size).to eq(1)
    expect(report[:uncovered_risks]).to include("routes.rb 有變更，請手動確認新增/修改的路由")
    expect(report[:no_spec_coverage]).to include("WorkOrder::Update")
  end

  it "builds tech report" do
    report = service.generate(company: company, pr_number: 65, format: "tech")

    expect(report[:view]).to eq("tech")
    expect(report[:impacts].first[:target_name]).to eq("WorkOrder::Update")
  end

  it "returns both reports" do
    report = service.generate(company: company, pr_number: 65, format: "both")

    expect(report[:qa][:view]).to eq("qa")
    expect(report[:tech][:view]).to eq("tech")
  end

  it "exports markdown checklist as tables with default playbook" do
    report = service.generate(
      company: company,
      pr_number: 65,
      format: "qa",
      pr_summary: {
        title: "Fix work order",
        body: "## Changed\n- update schedule fields",
        commented: "## Changed\n- update schedule fields",
        html_url: "https://github.com/AMASTek/TestCo/pull/65",
      },
    )
    markdown = service.to_markdown(report)

    expect(markdown).to include("修改摘要")
    expect(markdown).to include("update schedule fields")
    expect(markdown).to include("必測項目")
    expect(markdown).to include("建議迴歸")
    expect(markdown).to include("| # | 測試步驟 | 操作步驟 | 預期結果 | 權限 | Actor |")
    expect(markdown).to include("WorkOrder::Update")
    expect(markdown).to include("開啟編輯頁")
    expect(markdown).to include("資料庫欄位異動")
    expect(markdown).to include("未覆蓋風險")
    expect(markdown).to include("無 Spec 覆蓋")
  end

  it "formats create test step like menu > operation (path/new post)" do
    component_page = ManagementPage.create!(company: company, name: "component")
    action = ActionPage.create!(
      company: company,
      management_page: component_page,
      name: "Component::Create",
      operation_type: "新增",
      relate_model: ["Component"],
    )
    LocaleMetadata.find_or_create_by!(company: company) do |lm|
      lm.model_labels = { "component" => "單零件" }
      lm.menu_labels = { "component" => "單零件管理" }
      lm.perm_module_labels = { "component" => "單零件管理" }
      lm.perm_action_labels = { "edit" => "編輯" }
      lm.operation_type_labels = { "create" => "新增" }
      lm.imported_at = Time.current
    end
    company.locale_metadata.update!(
      model_labels: { "work_order" => "工單", "component" => "單零件" },
      menu_labels: { "work_order" => "工單管理", "component" => "單零件管理" },
      perm_module_labels: { "work_order" => "生產管理", "component" => "單零件管理" },
      perm_action_labels: { "edit" => "編輯" },
      operation_type_labels: { "create" => "新增", "update" => "編輯", "list" => "列表" },
    )
    menu = UiMenu.create!(
      company: company,
      namespace: "setting",
      menu_label: "單零件管理",
      module_label: "單零件管理",
      controller_path: "setting/components",
      perm_module: "component",
    )
    EntryPoint.create!(
      company: company,
      action_page: action,
      ui_menu: menu,
      controller_path: "setting/components",
      controller_action: "create",
      perm_module: "component",
      perm_action: "edit",
      channel: "web",
    )
    ImpactRecord.create!(
      company: company,
      pr_number: 77,
      source_type: "actor",
      source_name: "Component::Create",
      source_file_path: "app/actors/component/create.rb",
      target_type: "action_page",
      target_id: action.id,
      impact_level: "direct",
      reason: "PR 直接修改",
    )

    report = service.generate(company: company, pr_number: 77, format: "qa")
    item = report[:must_test].first

    expect(item[:test_step]).to eq("單零件管理 > 單零件管理 > 新增 (setting/components/new post)")
    expect(item[:operation_steps]).to include("開啟新增頁")
    expect(item[:expected_result]).to include("建立成功")
  end

  it "renders empty sections in markdown" do
    empty_report = {
      pr_number: 1,
      company: company.name,
      summary: { must_test: 0, suggested_regression: 0 },
      must_test: [],
      suggested_regression: [],
      pr_body: nil,
    }

    markdown = service.to_markdown(empty_report)

    expect(markdown).to include("_無_")
    expect(markdown).to include("修改摘要")
  end

  it "resolves relate model and entry point names in tech report" do
    relate_impact = ImpactRecord.create!(
      company: company,
      pr_number: 66,
      source_type: "model",
      source_name: "WorkOrder",
      source_file_path: "app/models/work_order.rb",
      target_type: "relate_model",
      target_id: RelateModel.create!(
        management_page: management_page,
        action_page: action_page,
        name: "WorkOrder",
      ).id,
      impact_level: "direct",
      reason: "direct model",
    )
    entry_impact = ImpactRecord.create!(
      company: company,
      pr_number: 66,
      source_type: "controller",
      source_name: "pms/work_orders",
      source_file_path: "app/controllers/pms/work_orders_controller.rb",
      target_type: "entry_point",
      target_id: entry_point.id,
      impact_level: "direct",
      reason: "controller",
    )

    report = service.generate(company: company, pr_number: 66, format: "tech")

    expect(report[:impacts].map { |i| i[:target_name] }).to include("WorkOrder", "pms/work_orders")
    expect(relate_impact).to be_persisted
    expect(entry_impact).to be_persisted
  end

  it "falls back to controller menu mapping when entry has no ui menu" do
    entry_point.update!(ui_menu: nil)

    report = service.generate(company: company, pr_number: 65, format: "qa")

    expect(report[:must_test].first[:menu_path]).to eq("生產管理 > 工單管理")
  end

  it "falls back to management page label when menu data is missing" do
    entry_point.update!(ui_menu: nil)
    ui_menu.destroy!

    report = service.generate(company: company, pr_number: 65, format: "qa")

    expect(report[:must_test].first[:menu_path]).to eq("工單管理")
  end
end
