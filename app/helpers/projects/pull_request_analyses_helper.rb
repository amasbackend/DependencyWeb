module Projects::PullRequestAnalysesHelper
  TAB_LABELS = {
    "test_scope" => "測試範圍",
    "changes" => "程式異動",
    "impact" => "影響範圍",
  }.freeze

  def tab_label(tab)
    TAB_LABELS.fetch(tab, tab)
  end

  # 程式異動 groups files by what kind of code they are — an engineer
  # scanning a 100-file PR looks for "the screens" or "the migrations" first.
  CHANGED_FILE_GROUPS = [
    [ "畫面（View／前端）", %r{\Aapp/(?:views|packs|javascript|assets/stylesheets)/} ],
    [ "後端程式", %r{\Aapp/} ],
    [ "資料庫", %r{\Adb/} ],
    [ "設定與語系", %r{\Aconfig/} ],
    [ "背景作業與工具", %r{\Alib/} ],
  ].freeze
  OTHER_FILE_GROUP = "其他（測試、開發設定）".freeze

  def changed_file_group(file_path)
    CHANGED_FILE_GROUPS.find { |_, pattern| file_path.match?(pattern) }&.first || OTHER_FILE_GROUP
  end

  def changed_file_groups_order
    CHANGED_FILE_GROUPS.map(&:first) + [ OTHER_FILE_GROUP ]
  end

  # Estimated LLM cost for display: NT$ when a USD→TWD rate is configured
  # (Llm::Pricing.usd_to_twd_rate), otherwise US$ — never a guessed rate.
  def llm_cost_text(cost_usd, rate: Llm::Pricing.usd_to_twd_rate)
    return "未設定單價" if cost_usd.nil?

    if rate
      number_to_currency(cost_usd.to_d * rate.to_d, unit: "NT$", precision: 2, delimiter: ",")
    else
      number_to_currency(cost_usd, unit: "US$", precision: 4, delimiter: ",")
    end
  end

  # Sum over every run of this PR (failed runs included — they were billed
  # too); nil if any run's cost is unknown.
  def total_llm_cost_usd(reports)
    costs = reports.map(&:estimated_cost_usd)
    costs.include?(nil) ? nil : costs.sum(BigDecimal("0"))
  end

  def changed_entity_label(entity)
    [ entity.class_name, entity.method_name ].compact_blank.join("#")
  end
end
