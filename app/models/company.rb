# frozen_string_literal: true

class Company < ApplicationRecord
  has_many :management_pages, dependent: :destroy
  has_many :action_pages, dependent: :destroy
end
