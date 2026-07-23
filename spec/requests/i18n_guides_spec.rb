# frozen_string_literal: true

require "rails_helper"

RSpec.describe I18nGuidesController, type: :request do
  it "renders skill copy page with recommended branch" do
    get i18n_guide_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("test/i18n")
    expect(response.body).to include("複製 AI 提示詞")
    expect(response.body).to include("專案 zh-TW I18n")
    expect(response.body).to include('name="project"')
    expect(response.body).to include('name="repo"')
    expect(response.body).not_to include("glossary.md")
  end

  it "includes free-text project and repo in prompt" do
    get i18n_guide_path(project: "DemoProject", repo: "AMASTek/DemoProject")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("DemoProject")
    expect(response.body).to include("AMASTek/DemoProject")
  end

  it "links to sync when project name matches a company" do
    company = Company.create!(name: "DemoProject", github_owner: "AMASTek")

    get i18n_guide_path(project: "DemoProject")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("前往同步母資料")
    expect(response.body).to include(management_page_path(company, view: "qa"))
  end
end
