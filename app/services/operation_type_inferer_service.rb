# frozen_string_literal: true

class OperationTypeInfererService
  SUFFIX_LABELS = {
    "Create" => "新增",
    "Update" => "編輯",
    "List" => "列表",
    "Find" => "檢視",
    "Show" => "檢視",
    "Destroy" => "刪除",
    "Archive" => "封存",
    "Import" => "匯入",
    "Export" => "匯出",
    "Start" => "開始",
    "Stop" => "結束",
    "Schedule" => "排程",
    "Sign" => "簽核",
    "Cancel" => "取消",
    "Finish" => "完成",
    "Sync" => "同步",
    "New" => "新增",
    "Finalize" => "定稿",
    "Sold" => "成交",
    "Copy" => "複製",
  }.freeze

  def self.infer(actor_name, labels: nil)
    new.infer(actor_name, labels: labels)
  end

  def infer(actor_name, labels: nil)
    suffix = actor_name.to_s.split("::").last
    return "" if suffix.blank?

    key = suffix.underscore
    label_map = stringify_keys(labels)

    label_map[key].presence ||
      label_map[suffix].presence ||
      SUFFIX_LABELS[suffix].presence ||
      suffix
  end

  def operation_key(actor_name)
    actor_name.to_s.split("::").last&.underscore
  end

  private

  def stringify_keys(labels)
    return {} if labels.blank?

    labels.transform_keys(&:to_s)
  end
end
