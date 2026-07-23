# frozen_string_literal: true

class LocaleMetadata < ApplicationRecord
  self.table_name = "locale_metadata"

  belongs_to :company

  validates :company_id, uniqueness: true
end
