# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetadataImportService do
  let(:company) { Company.create!(name: "TestCo", github_owner: "AMASTek", github_branch: "master") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }
  let!(:action_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Create",
      relate_model: ["WorkOrder"],
      source_file_path: "app/actors/work_order/create.rb",
      play_chain: ["WorkOrder::Check"],
    )
  end

  let(:github_double) { instance_double(GithubRepoService) }
  let(:locale_yaml) do
    <<~YAML
      zh-TW:
        activerecord:
          models:
            work_order: "工單"
          attributes:
            work_order:
              name: "名稱"
        perm_module:
          work_order: "生產管理"
        perm_action:
          edit: "編輯"
        operation_type:
          create: "新增"
          per_produce_time: "單件生產秒數"
        menu:
          work_order: "工單管理"
    YAML
  end

  let(:navbar_content) do
    <<~ERB
      modules = [
        {name: "工單管理", path: pms_work_orders_path, controller_path: "pms/work_orders", perm_module: "work_order", actions: %w[index new] },
      ]
    ERB
  end

  let(:routes_content) do
    'post "work_orders" # 新增工單'
  end

  let(:controller_content) do
    <<~RUBY
      class Pms::WorkOrdersController < ApplicationController
        before_action -> { permission_check("work_order", "edit") }, only: [:create]

        def create
          WorkOrder::Create.call!(params: work_order_params)
        end
      end
    RUBY
  end

  before do
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "config/locales/zh-TW/model.yml", "master")
                                                      .and_return({ content: locale_yaml })
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "config/locales/zh-TW.yml", "master")
                                                      .and_return(nil)
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "config/routes.rb", "master")
                                                      .and_return({ content: routes_content })
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "app/views", "master")
                                                         .and_return([{ path: "app/views/pms/_navbar.html.erb" }])
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "app/views/pms/_navbar.html.erb", "master")
                                                      .and_return({ content: navbar_content })
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "app/controllers", "master")
                                                         .and_return([{ path: "app/controllers/pms/work_orders_controller.rb" }])
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "app/controllers/pms/work_orders_controller.rb", "master")
                                                      .and_return({ content: controller_content })
  end

  it "imports locale, navbar, routes, and entry points" do
    result = described_class.new(github_service: github_double).import!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(result[:ui_menus]).to eq(1)
    expect(result[:entry_points]).to eq(1)
    expect(result[:locale]).to be true
    expect(company.ui_menus.first.menu_label).to eq("工單管理")
    expect(company.entry_points.first.action_page).to eq(action_page)
    expect(company.entry_points.first.controller_action).to eq("create")
    expect(action_page.reload.operation_type).to eq("新增")
    expect(company.entry_points.first.route_comment).to eq("新增工單")
    expect(company.locale_metadata.model_labels["work_order"]).to eq("工單")
    expect(company.locale_metadata.perm_action_labels["edit"]).to eq("編輯")
    expect(company.locale_metadata.operation_type_labels["per_produce_time"]).to eq("單件生產秒數")
    expect(company.locale_metadata.menu_labels["work_order"]).to eq("工單管理")
  end

  it "records warnings and continues when locale import fails" do
    allow(github_double).to receive(:get_file_content).and_return(nil)

    service = described_class.new(github_service: github_double)
    result = service.import!(company: company, owner: "AMASTek", repo: "TestCo", branch: "master")

    expect(result[:locale]).to be false
    expect(result[:warnings]).to be_empty
  end

  it "records navbar import warnings" do
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "app/views", "master")
                                                         .and_raise(StandardError, "navbar down")

    result = described_class.new(github_service: github_double).import!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(result[:warnings]).to include(a_string_including("Navbar 匯入失敗"))
  end

  it "records route import warnings" do
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "config/routes.rb", "master")
                                                      .and_raise(StandardError, "routes down")

    result = described_class.new(github_service: github_double).import!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(result[:warnings].last).to include("Routes 匯入失敗")
  end

  it "records entry point import warnings" do
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "app/controllers", "master")
                                                         .and_raise(StandardError, "controllers down")

    result = described_class.new(github_service: github_double).import!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(result[:warnings].last).to include("EntryPoint 匯入失敗")
  end

  it "returns failure summary when import raises" do
    service = described_class.new(github_service: github_double)
    allow(service).to receive(:clear_metadata!).and_raise(StandardError, "boom")

    result = service.import!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(result[:ui_menus]).to eq(0)
    expect(result[:warnings].last).to include("Metadata 匯入中斷")
  end
end
