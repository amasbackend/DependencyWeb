# frozen_string_literal: true

class ManagementPage < ApplicationRecord
  belongs_to :company
  has_many :action_pages, dependent: :destroy
end
