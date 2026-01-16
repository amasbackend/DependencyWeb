require "csv"

class ImportCsv
  attr_reader :file_path

  def initialize(file_path, company_name)
    @file_path = file_path
    @company_name = company_name
  end

  def read_and_import_management_and_action_pages
    raise "File not found: #{file_path}" unless File.exist?(file_path)

    current_management_page = nil
    action_page = nil

    company = Company.create!(name: @company_name)

    CSV.foreach(file_path, headers: true, encoding: "utf-8") do |row|
      # 如果管理頁面有值，更新當前的管理頁面
      if row["管理頁面(management_pages)"].present?
        current_management_page_name = row["管理頁面(management_pages)"]
        current_management_page = ManagementPage.find_or_create_by(company: company, name: current_management_page_name)
        puts "Imported ManagementPage: #{current_management_page_name}"
      end

      next unless current_management_page # 確保管理頁面存在

      action_page_name = row["商業邏輯(action_pages)"]
      if action_page_name.present?
        action_page = ActionPage.find_or_create_by(
          company: company,
          management_page: current_management_page,
          name: action_page_name,
          relate_action: parse_to_array(row["關聯邏輯(relate_action)"]),
          relate_model: parse_to_array(row["關聯模組(relate_model)"]),
          select_column: parse_to_array(row["使用欄位(select_column)"]),
          modify_column: parse_to_array(row["異動欄位(modify_column)"]),
          delete_column: parse_to_array(row["刪除記錄(delete_column)"]),
        )
        puts "Imported ActionPage: #{action_page_name}"
      end

      next unless action_page

      relate_model_name = row["關聯模組(relate_model)"]
      if relate_model_name.present?
        RelateModel.find_or_create_by(
          management_page: current_management_page,
          action_page: action_page,
          name: relate_model_name,
          select_column: parse_to_array(row["使用欄位(select_column)"]),
          modify_column: parse_to_array(row["異動欄位(modify_column)"]),
          delete_column: parse_to_array(row["刪除記錄(delete_column)"]),
        )
        puts "Imported RelateModel: #{relate_model_name}"
      end
    end
  end

  private

  # 將逗號或換行分隔的字串轉為陣列
  def parse_to_array(value)
    return [] if value.blank?

    value.split(/[\n,]/).map(&:strip).reject(&:blank?)
  end
end
