# frozen_string_literal: true

class FlagUpdateService
  def initialize
    @github_service = GithubAnalysisService.new
    @impact_analysis_service = ImpactAnalysisService.new
    @report_service = TestScopeReportService.new
  end

  # 更新指定 PR 的 flag 狀態，回傳 impact_summary
  def update_flags_from_pr(owner, repo, pr_number, company_name = "PrjJieZhou")
    company = Company.find_by(name: company_name)
    raise "找不到公司: #{company_name}" unless company

    reset_all_flags(company_name)

    analysis_result = @github_service.analyze_changes(owner, repo, pr_number)

    puts "分析結果："
    puts "變更檔案數量: #{analysis_result[:changed_files].count}"
    puts "Actor 變更: #{analysis_result[:actor_changes].count} 個"
    puts "Model 變更: #{analysis_result[:model_changes].count} 個"
    puts "Controller 變更: #{analysis_result[:controller_changes].count} 個"
    puts "Migration 變更: #{analysis_result[:migration_changes].count} 個"
    puts "Concern 變更: #{analysis_result[:concern_changes].count} 個"
    puts "Blueprint 變更: #{analysis_result[:blueprint_changes].count} 個"

    summary = @impact_analysis_service.analyze_and_persist!(
      company: company,
      pr_number: pr_number.to_i,
      actor_changes: analysis_result[:actor_changes],
      model_changes: analysis_result[:model_changes],
      controller_changes: analysis_result[:controller_changes],
      migration_changes: analysis_result[:migration_changes],
      concern_changes: analysis_result[:concern_changes],
      blueprint_changes: analysis_result[:blueprint_changes],
    )

    summary[:changed_files_count] = analysis_result[:changed_files].count
    persist_pr_analysis!(company, pr_number, analysis_result, summary)
    print_impact_summary(summary)
    summary
  end

  # 重置所有 flag 與 impact 記錄
  def reset_all_flags(company_name)
    company = Company.find_by(name: company_name)
    return unless company

    ActionPage.joins(:management_page)
              .where(management_pages: { company: company })
              .update_all(changed_flag: false)

    RelateModel.joins(:management_page)
               .where(management_pages: { company: company })
               .update_all(changed_flag: false)

    ImpactRecord.where(company: company).delete_all

    puts "已重置所有 flag 與 impact 記錄"
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

    impact_count = ImpactRecord.where(company: company).count

    puts "\nFlag 狀態統計："
    puts "變更的 ActionPage: #{action_pages_changed} 個"
    puts "變更的 RelateModel: #{relate_models_changed} 個"
    puts "Impact 記錄: #{impact_count} 筆"

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

  private

  def persist_pr_analysis!(company, pr_number, analysis_result, summary)
    qa_report = @report_service.generate(company: company, pr_number: pr_number.to_i, format: "qa")
    tech_report = @report_service.generate(company: company, pr_number: pr_number.to_i, format: "tech")

    PrAnalysis.save_snapshot!(
      company: company,
      pr_number: pr_number.to_i,
      impact_summary: summary,
      analysis_input: {
        changed_files_count: analysis_result[:changed_files].count,
        classified_counts: analysis_result[:classified_counts],
        column_impacts: analysis_result[:column_impacts],
        route_changes: analysis_result[:route_changes],
      },
      qa_report: qa_report,
      tech_report: tech_report,
    )
  rescue StandardError => e
    puts "⚠️  PR 分析快照儲存失敗（不影響 flag 更新）: #{e.message}"
  end

  def print_impact_summary(summary)
    puts "\n影響傳播摘要："
    puts "  總影響記錄: #{summary[:total_impacts]}"
    puts "  ActionPage 標記: #{summary[:action_pages_flagged]}"
    puts "  RelateModel 標記: #{summary[:relate_models_flagged]}"
    summary[:by_level]&.each do |level, count|
      puts "  #{level}: #{count}" if count.positive?
    end
    puts "Flag 更新完成"
  end
end
