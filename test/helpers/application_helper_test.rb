require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "status_badge renders a success variant for ready" do
    html = status_badge("ready", "就緒")

    assert_match "bg-emerald-100", html
    assert_match "就緒", html
  end

  test "status_badge renders a danger variant for failed" do
    html = status_badge("failed", "失敗")

    assert_match "bg-red-100", html
  end

  test "status_badge renders a neutral variant for statuses without an explicit mapping" do
    html = status_badge("pending", "待處理")

    assert_match "bg-slate-100", html
  end
end
