# frozen_string_literal: true

class FlagUpdateService
  def initialize
    @github_service = GithubAnalysisService.new
  end

  # 更新指定 PR 的 flag 狀態
  def update_flags_from_pr(owner, repo, pr_number, company_name = "PrjJieZhou")
    # 先重置所有 flag
    reset_all_flags(company_name)

    # 分析 GitHub PR 變更
    analysis_result = @github_service.analyze_changes(owner, repo, pr_number)

    puts "分析結果："
    puts "變更檔案數量: #{analysis_result[:changed_files].count}"
    puts "Actor 變更: #{analysis_result[:actor_changes].count} 個"
    puts "Model 變更: #{analysis_result[:model_changes].count} 個"

    # 更新 ActionPage 的 flag
    update_action_page_flags(analysis_result[:actor_changes], company_name)

    # 更新 RelateModel 的 flag
    update_relate_model_flags(analysis_result[:model_changes], company_name)

    puts "Flag 更新完成"
  end

  # 重置所有 flag
  def reset_all_flags(company_name)
    company = Company.find_by(name: company_name)
    return unless company

    ActionPage.joins(:management_page)
              .where(management_pages: { company: company })
              .update_all(changed_flag: false)

    RelateModel.joins(:management_page)
               .where(management_pages: { company: company })
               .update_all(changed_flag: false)

    puts "已重置所有 flag"
  end

  # 更新 ActionPage 的 flag
  def update_action_page_flags(actor_changes, company_name)
    company = Company.find_by(name: company_name)
    return unless company

    puts "actor_changes: #{actor_changes}"
    changed_actors = actor_changes.map { |change| change[:actor_name] }

    # 更新對應的 ActionPage
    ActionPage.joins(:management_page)
              .where(management_pages: { company: company })
              .where(name: changed_actors)
              .update_all(changed_flag: true)

    puts "已更新 #{changed_actors.count} 個 ActionPage 的 flag"
  end

  # 更新 RelateModel 的 flag
  def update_relate_model_flags(model_changes, company_name)
    company = Company.find_by(name: company_name)
    return unless company

    changed_models = model_changes.map { |change| change[:model_name] }
    # 更新對應的 RelateModel
    RelateModel.joins(:management_page)
               .where(management_pages: { company: company })
               .where(name: changed_models)
               .update_all(changed_flag: true)

    puts "已更新 #{changed_models.count} 個 RelateModel 的 flag"
  end

  # 顯示 flag 狀態統計
  def show_flag_statistics(company_name = "PrjJieZhou")
    company = Company.find_by(name: company_name)
    return unless company

    action_pages_changed = ActionPage.joins(:management_page)
                                     .where(management_pages: { company: company })
                                     .where(changed_flag: true)
                                     .count

    relate_models_changed = RelateModel.joins(:management_page)
                                       .where(management_pages: { company: company })
                                       .where(changed_flag: true)
                                       .count

    puts "\nFlag 狀態統計："
    puts "變更的 ActionPage: #{action_pages_changed} 個"
    puts "變更的 RelateModel: #{relate_models_changed} 個"

    # 顯示詳細的變更清單
    if action_pages_changed.positive?
      puts "\n變更的 ActionPage 清單："
      ActionPage.joins(:management_page)
                .where(management_pages: { company: company })
                .where(changed_flag: true)
                .each do |action_page|
                  puts "  - #{action_page.management_page.name}/#{action_page.name}"
      end
    end

    return unless relate_models_changed.positive?

    puts "\n變更的 RelateModel 清單："
    RelateModel.joins(:management_page)
               .where(management_pages: { company: company })
               .where(changed_flag: true)
               .each do |relate_model|
                 puts "  - #{relate_model.management_page.name}/#{relate_model.action_page.name}/#{relate_model.name}"
    end
  end
end
