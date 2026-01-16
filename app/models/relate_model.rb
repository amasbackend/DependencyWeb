# frozen_string_literal: true

class RelateModel < ApplicationRecord
  serialize :select_column, Array
  serialize :modify_column, Array
  serialize :delete_column, Array

  belongs_to :action_page
  belongs_to :management_page
end
