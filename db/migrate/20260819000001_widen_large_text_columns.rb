class WidenLargeTextColumns < ActiveRecord::Migration[7.1]
  # MySQL's default TEXT column caps at 65,535 bytes. Real Graphify output
  # (graph.json / GRAPH_REPORT.md) for a 1,200+ entity codebase blows past
  # that — confirmed via a live run against AMASTek/PrjJieZhou (Phase 10),
  # which failed with "Data too long for column 'raw_content'". A large PR
  # diff's raw patch, or a fully rendered test report, can hit the same
  # ceiling. LONGTEXT (size: :long) raises the cap to ~4GB.
  def change
    change_column :graphify_artifacts, :raw_content, :text, size: :long
    change_column :changed_files, :patch, :text, size: :long
    change_column :test_reports, :markdown_content, :text, size: :long
  end
end
