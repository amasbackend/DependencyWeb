# frozen_string_literal: true

# lib/tasks/import_management_pages_and_action_pages.rake
namespace :import do
  desc "Import management and action pages from the CSV file in lib/assets"
  task company: :environment do
    company = ENV.fetch("company")
    file_path = Rails.root.join("lib", "assets", "#{company}.csv")

    begin
      importer = ImportCsv.new(file_path, company)
      importer.read_and_import_management_and_action_pages
      puts "Import completed!"
    rescue StandardError => e
      puts "Error during import: #{e.message}"
    end
  end
end
