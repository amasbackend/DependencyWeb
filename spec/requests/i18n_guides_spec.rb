# frozen_string_literal: true

require "rails_helper"

RSpec.describe I18nGuidesController, type: :request do
  it "renders skill copy page with recommended branch" do
    get i18n_guide_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("test/i18n")
    expect(response.body).to include("複製 AI 提示詞")
    expect(response.body).to include("RelateDoc I18n")
    expect(response.body).not_to include("glossary.md")
  end

  it "includes selected company in prompt" do
    company = Company.create!(name: "DemoProject", github_owner: "AMASTek")

    get i18n_guide_path(company_id: company.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("DemoProject")
    expect(response.body).to include("AMASTek/DemoProject")
  end
end
