# frozen_string_literal: true

module CodeAnalysis
  class ImportExtendedRelations < Actor
    input :company
    input :owner
    input :repo
    input :branch

    output :summary

    def call
      service = ExtendedRelationService.new
      self.summary = service.enrich!(
        company: company,
        owner: owner,
        repo: repo,
        branch: branch,
      )

      puts "Extended relations: spec #{summary[:specs_matched]} 個, concern 關聯 #{summary[:shared_concerns]} 筆"
      summary[:warnings]&.each do |warning|
        puts "⚠️  #{warning}"
        Rails.logger.warn("[ImportExtendedRelations] #{warning}")
      end
    rescue StandardError => e
      puts "⚠️  Extended relations 略過: #{e.message}"
      self.summary = { specs_matched: 0, shared_concerns: 0, warnings: [e.message] }
    end
  end
end
