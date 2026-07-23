# frozen_string_literal: true

module CodeAnalysis
  class RelationsFromGithub < Actor
    input :project_name, default: "PrjNO"
    input :owner
    input :repo
    input :branch, default: "main"
    input :existing_company, default: nil

    output :all_action_classes
    output :all_model_classes
    output :analysis_results
    output :company
    output :statistics

    play :collect_classes,
         :analyze_management_pages,
         :import_to_database,
         :import_metadata,
         :import_extended_relations,
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
        github_owner: owner,
        github_branch: branch,
        analysis_results: analysis_results,
        existing_company: existing_company,
      )

      fail!(error: result.error) unless result.success?

      self.company = result.company
      self.statistics = result.statistics
    end

    def import_metadata
      return unless company

      metadata_result = CodeAnalysis::ImportMetadata.result(
        company: company,
        owner: owner,
        repo: repo,
        branch: branch,
      )

      return if metadata_result.success?

      puts "⚠️  Metadata 匯入警告: #{metadata_result.error}"
    end

    def import_extended_relations
      return unless company

      result = CodeAnalysis::ImportExtendedRelations.result(
        company: company,
        owner: owner,
        repo: repo,
        branch: branch,
      )

      return if result.success?

      puts "⚠️  Extended relations 警告: #{result.error}"
    end

    def display_statistics
      CodeAnalysis::DisplayStatistics.result(analysis_results: analysis_results)
    end
  end
end
