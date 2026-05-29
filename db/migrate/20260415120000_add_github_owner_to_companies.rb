# frozen_string_literal: true

class AddGithubOwnerToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :github_owner, :string
  end
end
