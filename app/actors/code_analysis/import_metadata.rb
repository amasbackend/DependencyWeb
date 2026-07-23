# frozen_string_literal: true

module CodeAnalysis
  class ImportMetadata < Actor
    input :company
    input :owner
    input :repo
    input :branch, default: "main"

    output :metadata_summary

    def call
      puts "\n開始匯入 QA metadata（best-effort）..."

      service = MetadataImportService.new
      self.metadata_summary = service.import!(
        company: company,
        owner: owner,
        repo: repo,
        branch: branch,
      )

      puts "QA metadata: 選單 #{metadata_summary[:ui_menus]} 個, EntryPoint #{metadata_summary[:entry_points]} 個"
      service.warnings.each do |w|
        puts "⚠️  #{w}"
        Rails.logger.warn("[ImportMetadata] #{w}")
      end
    end
  end
end
