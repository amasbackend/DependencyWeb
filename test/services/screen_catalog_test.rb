require "test_helper"

class ScreenCatalogTest < ActiveSupport::TestCase
  test "catalogs one screen per controller action with a view, skipping partials and controller-less views" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot)

    assert_equal %w[orders#index orders#new], catalog.screens.keys.sort
  end

  test "names a screen by its menu link and heading, inheriting the list page's menu for new" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot)

    assert_equal "訂單管理", catalog["orders#index"].display_name
    new_screen = catalog["orders#new"]
    assert_equal "訂單管理", new_screen.menu_name
    assert_equal "新增訂單", new_screen.title # the "*為必填欄位" hint is dropped
    assert_equal "訂單管理 › 新增訂單（/orders/new）", new_screen.page_path
  end

  test "takes the URL from the route comment above the action" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot)

    assert_equal "/orders", catalog["orders#index"].url
    assert_equal "/orders/new", catalog["orders#new"].url
  end

  test "follows render partials and mounted Vue components into the screen's source files and labels" do
    new_screen = ScreenCatalog.call(snapshot: screen_fixture_snapshot)["orders#new"]

    assert_includes new_screen.source_files, "app/views/orders/_form.html.erb"
    assert_includes new_screen.source_files, "app/packs/src/javascripts/orders/OrderForm.vue"
    assert_includes new_screen.source_files, "app/packs/src/javascripts/orders/form.js" # the mount script
    assert_includes new_screen.labels, "數量"
    assert_includes new_screen.labels, "送出"
    assert_includes new_screen.labels, "新增訂單" # the link text that leads here
  end

  test "excludes code comments from labels" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot)

    assert_not catalog.all.flat_map(&:labels).any? { |l| l.include?("開發註解") }
  end

  test "records the endpoints a page's Vue code calls" do
    new_screen = ScreenCatalog.call(snapshot: screen_fixture_snapshot)["orders#new"]

    assert_includes new_screen.endpoints, "orders#create"
  end

  test "screens_for_action maps a non-GET action to the screen that submits to it" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot)

    assert_equal [ "orders#new" ], catalog.screens_for_action("orders#create").map(&:key)
    assert_empty catalog.screens_for_action("api/machines#report")
  end

  # The other common mounting style: a script createApp()s a component onto
  # an element id, labels come from i18n keys, and a page declares itself via
  # a pageWatcher-style { controller:, action: } block.
  def id_mount_files
    {
      "app/controllers/stocks_controller.rb" => "class StocksController < ApplicationController\n  def index\n  end\n\n  def tag\n    render \"stocks/labels/tag\"\n  end\nend\n",
      "app/views/stocks/index.html.erb" => %(<h3><%= t('menu.stocks') %></h3>\n<div id="stocks-search"></div>\n<div id="stock-print-tag-<%= 1 %>"></div>\n<span><%= t('.hint') %></span>\n),
      "app/views/stocks/labels/tag.html.erb" => "<p>標籤</p>\n",
      "app/packs/src/javascripts/stocks/stocks.js" => <<~JS,
        import StocksSearch from '@/src/vueComponent/stocks/StocksSearch.vue'
        import StockPrintTag from '@/src/vueComponent/stocks/StockPrintTag.vue'
        pageWatcher({ controller: 'stocks', action: ['index'], handler () {} })
        const mountSearch = () => {
          const el = document.getElementById('stocks-search')
          createApp(StocksSearch, {}).mount(el)
        }
        document.querySelectorAll('[id^="stock-print-tag-"]').forEach((el) => createApp(StockPrintTag).mount(el))
      JS
      "app/packs/src/vueComponent/stocks/StocksSearch.vue" => "<template><button>{{ i18n.t('stocks.search') }}</button></template>\n<script>$.ajax({ url: '/stocks' })</script>\n",
      "app/packs/src/vueComponent/stocks/StockPrintTag.vue" => "<template><button>列印</button></template>\n",
      "config/locales/zh-TW/view.yml" => "zh-TW:\n  menu:\n    stocks: 庫存查詢\n  stocks:\n    search: 搜尋\n    index:\n      hint: 請輸入批號\n",
    }
  end

  test "follows createApp() mounts onto element ids, including id-prefix mounts" do
    screen = ScreenCatalog.call(snapshot: screen_fixture_snapshot(id_mount_files))["stocks#index"]

    assert_includes screen.source_files, "app/packs/src/vueComponent/stocks/StocksSearch.vue"
    assert_includes screen.source_files, "app/packs/src/vueComponent/stocks/StockPrintTag.vue"
    assert_includes screen.source_files, "app/packs/src/javascripts/stocks/stocks.js"
    assert_includes screen.endpoints, "stocks#index"
  end

  test "translates i18n keys (absolute, relative and from Vue) into labels and the heading" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot(id_mount_files))
    screen = catalog["stocks#index"]

    assert_equal "庫存查詢", screen.title
    assert_includes screen.labels, "搜尋"
    assert_includes screen.labels, "請輸入批號"
    assert_equal({ referenced: 3, resolved: 3 }, catalog.i18n_stats)
  end

  test "an action that renders another directory's template is a screen built from that template" do
    screen = ScreenCatalog.call(snapshot: screen_fixture_snapshot(id_mount_files))["stocks#tag"]

    assert_equal [ "app/views/stocks/labels/tag.html.erb" ], screen.source_files
    assert_includes screen.labels, "標籤"
  end

  test "substitutes app label constants used in link texts and views" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot(
      "config/initializers/definitions.rb" => "WORKAREA = {\n  orders: \"原料加工\",\n}\n",
      "app/views/layouts/_navbar.html.erb" => %(<%= link_to "\#{WORKAREA[:orders]} 工單", orders_path %>\n),
      "app/views/orders/index.html.erb" => %(<%= render "/layouts/navbar" %>\n<p><%= WORKAREA[:orders] %></p>\n),
    ))

    assert_equal "原料加工 工單", catalog["orders#index"].menu_name
    assert_includes catalog["orders#index"].labels, "原料加工"
  end

  test "a back-to-list link's text names the list without the 回 prefix" do
    catalog = ScreenCatalog.call(snapshot: screen_fixture_snapshot(
      "app/views/layouts/_navbar.html.erb" => "<nav></nav>\n",
      "app/views/orders/new.html.erb" => %(<%= link_to "回訂單列表", orders_path %>\n),
    ))

    assert_equal "訂單列表", catalog["orders#index"].menu_name
  end
end
