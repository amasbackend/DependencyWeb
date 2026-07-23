# frozen_string_literal: true

class AddSyncFieldsToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :github_branch, :string, default: "master", null: false
    add_column :companies, :last_synced_at, :datetime
  end
end
