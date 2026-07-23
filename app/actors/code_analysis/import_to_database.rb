# frozen_string_literal: true

module CodeAnalysis
  class ImportToDatabase < Actor
    input :project_name
    input :github_owner
    input :github_branch, default: "master"
    input :analysis_results
    input :existing_company, default: nil

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
      if existing_company
        existing_company.shared_concerns.destroy_all
        existing_company.entry_points.destroy_all
        existing_company.ui_menus.destroy_all
        existing_company.locale_metadata&.destroy
        existing_company.action_pages.destroy_all
        existing_company.management_pages.destroy_all
        self.company = existing_company
        return
      end

      Company.where(name: project_name).destroy_all
    end

    def create_company
      if company
        company.update!(
          github_owner: github_owner,
          github_branch: github_branch,
          last_synced_at: Time.current,
        )
        return
      end

      self.company = Company.create!(
        name: project_name,
        github_owner: github_owner,
        github_branch: github_branch,
        last_synced_at: Time.current,
      )
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
          source_file_path: action_page_info[:source_file_path],
          play_chain: action_page_info[:play_chain] || [],
          operation_type: action_page_info[:operation_type],
          blueprint_names: action_page_info[:blueprint_names] || [],
          channel: infer_channel(action_page_name, action_page_info[:source_file_path]),
        )

        create_shared_concerns(action_page, action_page_info[:concern_names])
        create_relate_models(management_page, action_page, action_page_info)
      end
    end

    def extract_relate_model_keys(relate_models)
      relate_models.is_a?(Hash) ? relate_models.keys : []
    end

    def infer_channel(action_page_name, source_file_path)
      return "api" if action_page_name.start_with?("Api::")
      return "api" if source_file_path.to_s.include?("/actors/api/")

      "web"
    end

    def create_shared_concerns(action_page, concern_names)
      Array(concern_names).each do |concern_name|
        SharedConcern.create!(
          company: company,
          action_page: action_page,
          concern_name: concern_name,
          concern_file_path: "app/actors/concerns/#{concern_name.underscore}.rb",
        )
      end
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
