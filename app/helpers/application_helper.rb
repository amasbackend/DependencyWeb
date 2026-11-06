module ApplicationHelper
  STATUS_BADGE_VARIANT = {
    "ready" => :success,
    "completed" => :success,
    "failed" => :danger,
    "llm_failed" => :danger,
  }.freeze

  def status_badge(status, text)
    variant = STATUS_BADGE_VARIANT.fetch(status.to_s, :neutral)
    render "shared/badge", text: text, variant: variant
  end

  SOURCE_BADGE_VARIANT = {
    "llm_inferred" => :warning,
  }.freeze

  def source_badge(source, text)
    variant = SOURCE_BADGE_VARIANT.fetch(source.to_s, :neutral)
    render "shared/badge", text: text, variant: variant
  end

  def entity_type_badge(text)
    render "shared/badge", text: text, variant: :neutral
  end

  RISK_BADGE_VARIANT = {
    "high" => :danger,
    "medium" => :warning,
    "low" => :neutral,
  }.freeze

  def risk_badge(risk_level, text)
    variant = RISK_BADGE_VARIANT.fetch(risk_level.to_s, :neutral)
    render "shared/badge", text: text, variant: variant
  end

  CASE_TYPE_BADGE_VARIANT = {
    "core_change" => :danger,
    "direct_impact" => :warning,
  }.freeze

  def case_type_badge(case_type, text)
    variant = CASE_TYPE_BADGE_VARIANT.fetch(case_type.to_s, :neutral)
    render "shared/badge", text: text, variant: variant
  end

  CHANGE_KIND_BADGE_VARIANT = {
    "added" => :success,
    "removed" => :danger,
  }.freeze

  def change_kind_badge(change_kind, text)
    variant = CHANGE_KIND_BADGE_VARIANT.fetch(change_kind.to_s, :neutral)
    render "shared/badge", text: text, variant: variant
  end

  DIFF_LINE_ROW_CLASS = {
    "add" => "bg-emerald-50",
    "remove" => "bg-red-50",
  }.freeze

  def diff_line_row_class(type)
    DIFF_LINE_ROW_CLASS.fetch(type.to_s, "bg-white")
  end

  DIFF_LINE_PREFIX = { "add" => "+", "remove" => "-" }.freeze

  def diff_line_prefix(type)
    DIFF_LINE_PREFIX.fetch(type.to_s, " ")
  end

  # entity_type here comes from GraphifyGraphIndex#entity_type_for, which
  # returns nil for any node outside the recognized Rails directories (routes
  # and views notably have no Graphify node at all — see CodeEntityExtractor)
  # — that's a real "we don't know", not a missing translation.
  def code_entity_type_label(entity_type)
    return "未知類型" if entity_type.blank?

    I18n.t("enumerize.code_entity.entity_type.#{entity_type}", default: entity_type)
  end
end
