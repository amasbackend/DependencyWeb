# frozen_string_literal: true

require "rails_helper"

RSpec.describe QaDisplayHelper, type: :helper do
  let(:company) { Company.create!(name: "HelperCo", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }
  let!(:locale_metadata) do
    LocaleMetadata.create!(
      company: company,
      model_labels: { "work_order" => "工單" },
      attribute_labels: { "work_order" => { "estimated_hours" => "預估工時" } },
      perm_module_labels: { "work_order" => "生產管理" },
      perm_action_labels: { "edit" => "編輯" },
      operation_type_labels: { "list" => "列表", "general_predict" => "通用預測" },
      menu_labels: { "work_order" => "工單管理" },
      state_labels: {},
      imported_at: Time.current,
    )
  end
  let!(:ui_menu) do
    UiMenu.create!(
      company: company,
      namespace: "pms",
      menu_label: "工單管理",
      module_label: "生產管理",
      controller_path: "pms/work_orders",
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
      channel: "web",
    )
  end

  before do
    allow(helper).to receive(:params).and_return(ActionController::Parameters.new(view: view_param))
  end

  let(:view_param) { nil }
  let(:entry_points_by_action) { { action_page.id => entry_point } }
  let(:ui_menus_by_controller) { { "pms/work_orders" => [ui_menu] } }

  describe "#qa_view_mode" do
    it "defaults to qa view" do
      expect(helper.qa_view_mode).to eq("qa")
    end

    it "switches to tech view" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(view: "tech"))

      expect(helper.qa_view_mode).to eq("tech")
    end
  end

  describe "#qa_model_label" do
    it "returns localized labels with fallbacks" do
      expect(helper.qa_model_label(company, "WorkOrder")).to eq("工單")
      expect(helper.qa_model_label(company, "Unknown")).to eq("Unknown")
    end

    it "handles missing locale metadata" do
      fresh_company = Company.create!(name: "NoLocale", github_owner: "AMASTek")

      expect(helper.qa_model_label(fresh_company, "work_order")).to eq("work_order")
    end
  end

  describe "#qa_model_list" do
    it "joins localized model names" do
      expect(helper.qa_model_list(company, %w[WorkOrder Unknown])).to eq("工單, Unknown")
    end
  end

  describe "#qa_column_labels" do
    it "returns localized column labels" do
      expect(helper.qa_column_labels(company, "WorkOrder", %w[estimated_hours])).to eq("預估工時")
    end

    it "returns raw columns when blank" do
      expect(helper.qa_column_labels(company, "WorkOrder", [])).to eq("")
    end

    it "falls back to raw column names" do
      expect(helper.qa_column_labels(company, "WorkOrder", %w[legacy_field])).to eq("legacy_field")
    end
  end

  describe "#qa_menu_path" do
    it "prefers ui menu labels" do
      expect(helper.qa_menu_path(company, action_page, entry_points_by_action, ui_menus_by_controller))
        .to eq("生產管理 > 工單管理")
    end

    it "falls back to controller menu mapping" do
      entry_point.update!(ui_menu: nil)

      expect(helper.qa_menu_path(company, action_page, entry_points_by_action, ui_menus_by_controller))
        .to eq("生產管理 > 工單管理")
    end

    it "falls back to management page label" do
      entry_point.update!(ui_menu: nil)
      ui_menu.destroy!

      expect(helper.qa_menu_path(company, action_page, entry_points_by_action, {}))
        .to eq("工單管理")
    end
  end

  describe "#qa_management_page_label" do
    it "prefers menu then model labels" do
      expect(helper.qa_management_page_label(company, management_page)).to eq("工單管理")
    end
  end

  describe "#qa_operation_label" do
    it "uses operation type or infers from actor name" do
      expect(helper.qa_operation_label(company, action_page)).to eq("編輯")
      expect(helper.qa_operation_label(company, ActionPage.new(name: "WorkOrder::List"))).to eq("列表")
      expect(helper.qa_operation_label(company, ActionPage.new(name: "CncMachine::Find"))).to eq("檢視")
    end

    it "re-resolves english-stored leaf names via locale" do
      action_page.update!(operation_type: "GeneralPredict", name: "Component::GeneralPredict")

      expect(helper.qa_operation_label(company, action_page)).to eq("通用預測")
    end
  end

  describe "#qa_permission_label" do
    it "formats permission labels with locale" do
      expect(helper.qa_permission_label(company, entry_point)).to eq("生產管理 / 編輯")
      expect(helper.qa_permission_label(company, nil)).to eq("—")
    end
  end

  describe "#qa_entry_point_for" do
    it "returns mapped entry point" do
      expect(helper.qa_entry_point_for(action_page, entry_points_by_action)).to eq(entry_point)
      expect(helper.qa_entry_point_for(ActionPage.new(id: 0), {})).to be_nil
    end
  end

  describe "#qa_entry_summary" do
    it "formats web and api entry summaries" do
      expect(helper.qa_entry_summary(entry_point)).to eq("pms/work_orders#update")

      api_entry = entry_point.dup
      api_entry.channel = "api"
      expect(helper.qa_entry_summary(api_entry)).to eq("API pms/work_orders#update")
      expect(helper.qa_entry_summary(nil)).to eq("—")
    end
  end
end
