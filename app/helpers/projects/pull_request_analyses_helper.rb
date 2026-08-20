module Projects::PullRequestAnalysesHelper
  # §41's tab labels.
  TAB_LABELS = {
    "test_scope" => "測試範圍",
    "changes" => "修改內容",
    "business" => "業務視圖",
    "technical" => "技術視圖",
    "graphify" => "Graphify",
    "raw_diff" => "Raw Diff",
  }.freeze

  def tab_label(tab)
    TAB_LABELS.fetch(tab, tab)
  end
end
