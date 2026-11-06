require "test_helper"

class RoutesFileParserTest < ActiveSupport::TestCase
  # Modeled directly on patterns confirmed against the real target repo's
  # actual config/routes.rb — nested namespaces, a resources block whose
  # trailing comment names the whole resource, member/collection custom
  # actions nested inside that block with their own comments, an explicit
  # verb route with a route TARGET containing a literal "#" that must not be
  # mistaken for the comment marker, and root.
  FIXTURE = <<~RUBY
    Rails.application.routes.draw do
      root to: "session#index"
      get "login", to: "session#new"

      namespace :api do
        namespace :pms do
          post "work_orders/create" => "work_orders#create" # 新增工單
        end
      end

      namespace :setting do
        resources :customers, except: [:destroy] # 客戶管理
        resources :materials, except: [:destroy] do # 材料管理
          get :history_prices, on: :member # 取得歷史報價
          get :types, on: :member # 取得所有類型
        end
      end

      resources :orders, only: [:index, :show]
    end
  RUBY

  setup do
    @path = Tempfile.new([ "routes", ".rb" ]).tap { |f| f.write(FIXTURE); f.rewind; f.close }.path
    @result = RoutesFileParser.call(routes_path: @path)
  end

  teardown { File.delete(@path) if @path && File.exist?(@path) }

  test "resolves root and plain verb routes with no namespace" do
    assert_includes @result[:routes], RoutesFileParser::Route.new(
      controller: "SessionController", action: "index", comment: nil, standard: false
    )
    assert_includes @result[:routes], RoutesFileParser::Route.new(
      controller: "SessionController", action: "new", comment: nil, standard: false
    )
  end

  test "qualifies controller names through nested namespace blocks" do
    route = @result[:routes].find { |r| r.action == "create" && r.controller == "Api::Pms::WorkOrdersController" }
    assert route
  end

  test "does not mistake the '#' inside a route target for a comment marker" do
    route = @result[:routes].find { |r| r.controller == "Api::Pms::WorkOrdersController" }
    assert_equal "新增工單", route.comment
  end

  test "expands resources with except: into the remaining standard CRUD actions" do
    actions = @result[:routes].select { |r| r.controller == "Setting::CustomersController" }.map(&:action)
    assert_equal %w[index show new create edit update].sort, actions.sort
  end

  test "captures the resources-line comment as a resource-level (module) comment, not a per-action one" do
    assert_equal "客戶管理", @result[:resource_comments]["Setting::CustomersController"]
    standard_action = @result[:routes].find { |r| r.controller == "Setting::CustomersController" && r.action == "index" }
    assert_nil standard_action.comment
  end

  test "captures member/collection custom actions nested inside a resources do...end block with their own comments" do
    custom = @result[:routes].find { |r| r.controller == "Setting::MaterialsController" && r.action == "history_prices" }
    assert custom
    assert_equal "取得歷史報價", custom.comment
    assert_not custom.standard
  end

  test "resources with only: restricts to just those actions" do
    actions = @result[:routes].select { |r| r.controller == "OrdersController" }.map(&:action)
    assert_equal %w[index show], actions.sort
  end

  test "a tool directive in the trailing-comment slot is not taken as a label" do
    path = Tempfile.new([ "routes", ".rb" ]).tap { |f| f.write(<<~RUBY); f.close }.path
      Rails.application.routes.draw do
        resources :assembles do # rubocop:disable Metrics/BlockLength
          get :print_tag, on: :member # 列印標籤
        end
      end
    RUBY

    result = RoutesFileParser.call(routes_path: path)

    assert_nil result[:resource_comments]["AssemblesController"]
    assert_equal "列印標籤", result[:routes].find { |r| r.action == "print_tag" }.comment
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
