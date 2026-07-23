# frozen_string_literal: true

class UiMenu < ApplicationRecord
  belongs_to :company
  has_many :entry_points, dependent: :nullify

  validates :menu_label, :controller_path, presence: true
end
