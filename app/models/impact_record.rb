# frozen_string_literal: true

class ImpactRecord < ApplicationRecord
  belongs_to :company

  TARGET_TYPES = %w[action_page relate_model entry_point].freeze
  SOURCE_TYPES = %w[actor model controller migration route concern blueprint].freeze
  IMPACT_LEVELS = %w[direct caller callee model_consumer caller_l2 concern].freeze

  validates :pr_number, :source_type, :source_name, :target_type, :target_id, :impact_level, presence: true
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :impact_level, inclusion: { in: IMPACT_LEVELS }

  scope :for_pr, ->(company_id, pr_number) { where(company_id: company_id, pr_number: pr_number) }
end
