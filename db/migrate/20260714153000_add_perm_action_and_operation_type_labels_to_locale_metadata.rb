# frozen_string_literal: true

class AddPermActionAndOperationTypeLabelsToLocaleMetadata < ActiveRecord::Migration[7.1]
  def change
    add_column :locale_metadata, :perm_action_labels, :json
    add_column :locale_metadata, :operation_type_labels, :json
    add_column :locale_metadata, :menu_labels, :json
  end
end
