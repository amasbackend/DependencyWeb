# frozen_string_literal: true

class ActionPage < ApplicationRecord
  serialize :relate_action, Array
  serialize :relate_model, Array
  serialize :select_column, Array
  serialize :modify_column, Array
  serialize :delete_column, Array

  belongs_to :company
  belongs_to :management_page
  has_many :relate_models, dependent: :destroy
end
