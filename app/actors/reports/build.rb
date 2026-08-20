module Reports
  # §39: assembles the presentation-ready view data Reports::RenderMarkdown
  # needs from the latest completed TestReport + its TestCases. Pure
  # computation, no external calls — everything here was already validated
  # and persisted by Llm::AnalyzeTestScope (Phase 12), so a failure here
  # means a genuine bug (e.g. no completed report exists yet), not a
  # transient/environment problem.
  class Build < Actor
    input :pull_request_analysis
    output :test_report
    output :report_data

    # §31's impact-level priority order, reused here to drive §39's
    # "建議測試順序" (suggested test order) — core changes and their direct
    # fallout first, regression checks last.
    CASE_TYPE_PRIORITY = %w[core_change direct_impact indirect_impact regression].freeze

    def call
      pull_request_analysis.update!(status: "building_report")

      report = latest_completed_report
      unless report
        fail_with(I18n.t("actor.reports.build.no_report"))
        return
      end

      self.test_report = report
      self.report_data = build_report_data(report)
    rescue StandardError => e
      fail_with(I18n.t("actor.reports.build.failed", message: e.message))
    end

    private

    def latest_completed_report
      pull_request_analysis.test_reports.where(status: "completed").order(created_at: :desc).first
    end

    def build_report_data(report)
      cases = report.test_cases.order(:position).to_a
      structured = report.structured_content || {}

      {
        summary_changes: Array(structured.dig("summary", "changes")),
        overview_rows: cases.map { |c| overview_row(c) },
        preparation: Array(structured["preparation"]),
        cases: cases,
        pass_criteria: Array(structured["pass_criteria"]),
        manual_checks: Array(structured["manual_checks"]),
        uncertain_items: Array(structured["uncertain_items"]),
        suggested_order_groups: suggested_order_groups(cases),
      }
    end

    def overview_row(test_case)
      {
        scenario: test_case.name,
        page_path: test_case.page_path,
        action_summary: Array(test_case.steps).join(" → "),
        verification_purpose: test_case.verification_purpose,
      }
    end

    def suggested_order_groups(cases)
      cases.group_by(&:case_type)
        .sort_by { |case_type, _| CASE_TYPE_PRIORITY.index(case_type) || CASE_TYPE_PRIORITY.size }
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "building_report")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
