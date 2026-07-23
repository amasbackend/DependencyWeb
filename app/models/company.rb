# frozen_string_literal: true

class Company < ApplicationRecord
  has_many :management_pages, dependent: :destroy
  has_many :action_pages, dependent: :destroy
  has_many :impact_records, dependent: :destroy
  has_many :pr_analyses, dependent: :destroy
  has_many :shared_concerns, dependent: :destroy
  has_many :ui_menus, dependent: :destroy
  has_many :entry_points, dependent: :destroy
  has_one :locale_metadata, dependent: :destroy
end
