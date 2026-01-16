# frozen_string_literal: true

module CodeAnalysis
  class RelationsFromGithub < Actor
    input :project_name, default: "PrjNO"
    input :owner
    input :repo
    input :branch, default: "main"

    output :all_action_classes
    output :all_model_classes
    output :analysis_results
    output :company
    output :statistics

    play :collect_classes,
         :analyze_management_pages,
         :import_to_database,
         :display_statistics

    private

    def collect_classes
      collect_action_classes_result = CodeAnalysis::CollectActionClassesFromGithub.result(
        owner: owner,
        repo: repo,
        branch: branch,
      )
      collect_model_classes_result = CodeAnalysis::CollectModelClassesFromGithub.result(
        owner: owner,
        repo: repo,
        branch: branch,
      )

      fail!(error: "無法收集 Action Classes") unless collect_action_classes_result.success?
      fail!(error: "無法收集 Model Classes") unless collect_model_classes_result.success?

      self.all_action_classes = collect_action_classes_result.action_classes
      self.all_model_classes = collect_model_classes_result.model_classes
    end

    def analyze_management_pages
      result = CodeAnalysis::AnalyzeManagementPagesFromGithub.result(
        owner: owner,
        repo: repo,
        branch: branch,
        all_action_classes: all_action_classes,
        all_model_classes: all_model_classes,
      )

      fail!(error: result.error) unless result.success?

      self.analysis_results = result.analysis_results
    end

    def import_to_database
      result = CodeAnalysis::ImportToDatabase.result(
        project_name: project_name,
        analysis_results: analysis_results,
      )

      fail!(error: result.error) unless result.success?

      self.company = result.company
      self.statistics = result.statistics
    end

    def display_statistics
      CodeAnalysis::DisplayStatistics.result(analysis_results: analysis_results)
    end
  end
end
