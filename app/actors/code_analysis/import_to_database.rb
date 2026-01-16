# frozen_string_literal: true

module CodeAnalysis
  class ImportToDatabase < Actor
    input :project_name
    input :analysis_results

    output :company
    output :statistics

    def call
      puts "\n開始匯入分析結果到資料庫..."

      delete_existing_records
      create_company
      create_management_pages
      generate_statistics

      display_import_results
    end

    private

    def delete_existing_records
      Company.where(name: project_name).destroy_all
    end

    def create_company
      self.company = Company.create!(name: project_name)
    end

    def create_management_pages
      analysis_results[:management_pages].each do |management_page_name, management_page_data|
        management_page = ManagementPage.create!(
          company: company,
          name: management_page_name,
        )

        create_action_pages(management_page, management_page_data)
      end
    end

    def create_action_pages(management_page, management_page_data)
      management_page_data[:action_pages].each do |action_page_name, action_page_info|
        relate_model_keys = extract_relate_model_keys(action_page_info[:relate_models])

        action_page = ActionPage.create!(
          company: company,
          management_page: management_page,
          name: action_page_name,
          relate_action: action_page_info[:relate_actions],
          relate_model: relate_model_keys,
          select_column: action_page_info[:select_column],
          modify_column: action_page_info[:modify_column],
          delete_column: action_page_info[:delete_column],
        )

        create_relate_models(management_page, action_page, action_page_info)
      end
    end

    def extract_relate_model_keys(relate_models)
      relate_models.is_a?(Hash) ? relate_models.keys : []
    end

    def create_relate_models(management_page, action_page, action_page_info)
      return unless action_page_info[:relate_models].is_a?(Hash)

      action_page_info[:relate_models].each_key do |model_name|
        RelateModel.create!(
          management_page: management_page,
          action_page: action_page,
          name: model_name,
        )
      end
    end

    def generate_statistics
      self.statistics = {
        management_pages_count: ManagementPage.where(company: company).count,
        action_pages_count: ActionPage.joins(:management_page).where(management_pages: { company: company }).count,
        relate_models_count: RelateModel.joins(:management_page).where(management_pages: { company: company }).count,
      }
    end

    def display_import_results
      puts "資料匯入完成"
      puts "公司: #{company.name}"
      puts "管理頁面: #{statistics[:management_pages_count]} 個"
      puts "動作頁面: #{statistics[:action_pages_count]} 個"
      puts "關聯模型: #{statistics[:relate_models_count]} 個"
    end
  end
end
