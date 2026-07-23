# frozen_string_literal: true

class SharedConcern < ApplicationRecord
  belongs_to :company
  belongs_to :action_page

  validates :concern_name, presence: true
end
