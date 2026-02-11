# frozen_string_literal: true

module ApplicationHelper
  # 將陣列轉成 UTF-8 安全字串後用 sep 連接，避免 DB 傳回 ASCII-8BIT 造成模板編碼錯誤
  def safe_join_utf8(arr, sep = ", ")
    return "" if arr.blank?
    arr.map { |s| s.to_s.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace) }.join(sep)
  end
end
