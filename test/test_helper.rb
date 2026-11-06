ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

# Safety net: a test that forgets with_scratch_repository_root must never
# fall through to the real storage/repositories (an unwrapped destroy test
# used to delete the real PrjJieZhou clone on every suite run).
Rails.application.config.x.repository_root = Dir.mktmpdir("test-repository-root")

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Sets the given ENV vars for the duration of the block, restoring the
    # previous values afterward via `ensure` regardless of how the block
    # exits — always use `ensure`, not a plain trailing assignment, or a
    # raised exception leaks the override into every later test in this
    # process (see docs/architecture_plan.md §8's ENV["PATH"] leak writeup).
    def with_env(vars)
      previous = vars.keys.index_with { |k| ENV[k] }
      vars.each { |k, v| ENV[k] = v }
      yield
    ensure
      previous.each { |k, v| ENV[k] = v }
    end

    # Points Repositories::* actors at a scratch tmpdir instead of real
    # storage/repositories for the duration of the block, so git operations in
    # tests never touch (or depend on) the real filesystem layout.
    def with_scratch_repository_root
      Dir.mktmpdir("repository-root") do |dir|
        previous = Rails.application.config.x.repository_root
        Rails.application.config.x.repository_root = dir
        yield Pathname.new(dir)
      ensure
        Rails.application.config.x.repository_root = previous
      end
    end

    # Builds a real, tiny local git repo (one commit on branch "main") to use
    # as a clone source in tests — real git plumbing, zero network/GitHub
    # dependency, satisfying project_plan.md §68's "never call GitHub in the
    # test suite" without falling back to a fully mocked GitCommand. Removed
    # automatically in teardown below.
    def build_fixture_git_repo
      dir = Dir.mktmpdir("fixture-repo")
      Dir.chdir(dir) do
        system("git", "init", "-q", exception: true)
        system("git", "checkout", "-q", "-b", "main", exception: true)
        system("git", "config", "user.email", "test@example.com", exception: true)
        system("git", "config", "user.name", "Test", exception: true)
        File.write("README.md", "hello")
        system("git", "add", "README.md", exception: true)
        system("git", "commit", "-q", "-m", "initial commit", exception: true)
      end
      (@fixture_git_repos ||= []) << dir
      dir
    end

    # A tiny real Ruby source tree (a model + a controller that calls it) for
    # exercising the real `graphify` CLI end-to-end without needing a git repo
    # at all — Graphify operates on plain files. Removed in teardown below.
    def build_fixture_code_dir
      dir = Dir.mktmpdir("fixture-code")
      FileUtils.mkdir_p(File.join(dir, "app", "models"))
      FileUtils.mkdir_p(File.join(dir, "app", "controllers"))
      File.write(File.join(dir, "app", "models", "user.rb"), <<~RUBY)
        class User < ApplicationRecord
          has_many :posts
        end
      RUBY
      File.write(File.join(dir, "app", "controllers", "users_controller.rb"), <<~RUBY)
        class UsersController < ApplicationController
          def show
            @user = User.find(params[:id])
          end
        end
      RUBY
      (@fixture_git_repos ||= []) << dir
      dir
    end

    # A small but realistic Rails-shaped git repo (model, controller, concern,
    # actor, view, routes.rb — one commit on branch "main") for exercising
    # Projects::IndexCode end-to-end: real git worktree, real graphify run,
    # real CodeEntityExtractor classification. Removed in teardown below.
    def build_fixture_rails_repo
      dir = Dir.mktmpdir("fixture-rails-repo")
      %w[app/models app/models/concerns app/controllers app/actors app/views/users].each do |sub|
        FileUtils.mkdir_p(File.join(dir, sub))
      end
      FileUtils.mkdir_p(File.join(dir, "config"))

      File.write(File.join(dir, "app", "models", "concerns", "trackable.rb"), <<~RUBY)
        module Trackable
        end
      RUBY
      File.write(File.join(dir, "app", "models", "user.rb"), <<~RUBY)
        class User < ApplicationRecord
          include Trackable
          has_many :posts
        end
      RUBY
      File.write(File.join(dir, "app", "controllers", "users_controller.rb"), <<~RUBY)
        class UsersController < ApplicationController
          def index
            @users = User.all
          end

          def show
            @user = User.find(params[:id])
          end

          def activate
            true
          end

          def archive
            true
          end
        end
      RUBY
      File.write(File.join(dir, "app", "actors", "users_update.rb"), <<~RUBY)
        class Users::Update
          def call
            true
          end
        end
      RUBY
      File.write(File.join(dir, "app", "views", "users", "index.html.erb"), "<h1>Users</h1>\n")
      # Comments follow the pattern confirmed against the real target repo's
      # actual routes.rb: a resources-line comment names the whole resource
      # (used for BusinessModule naming), a per-action comment on a nested
      # member/collection route names that one feature directly, and one
      # action (archive) is deliberately left uncommented to exercise the
      # LLM-inference path in Projects::BuildBusinessFeatures.
      File.write(File.join(dir, "config", "routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          resources :users, only: [:index, :show] do # 使用者管理
            get :activate, on: :member # 啟用使用者
            get :archive, on: :member
          end
          root "users#index"
        end
      RUBY

      Dir.chdir(dir) do
        system("git", "init", "-q", exception: true)
        system("git", "checkout", "-q", "-b", "main", exception: true)
        system("git", "config", "user.email", "test@example.com", exception: true)
        system("git", "config", "user.name", "Test", exception: true)
        system("git", "add", "-A", exception: true)
        system("git", "commit", "-q", "-m", "initial commit", exception: true)
      end
      (@fixture_git_repos ||= []) << dir
      dir
    end

    teardown do
      @fixture_git_repos&.each { |dir| FileUtils.remove_entry(dir) if File.exist?(dir) }
    end

    # Counts SQL queries issued inside the block and asserts it stays at or
    # below `max` — used to catch N+1 regressions on pages that render one
    # row per record (e.g. business feature tables), where a reintroduced
    # per-row query would scale with the fixture size and blow past a small
    # fixed cap, while a properly eager-loaded page would not.
    def assert_query_count(max:)
      count = 0
      counter = ->(*) { count += 1 }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }

      assert count <= max, "expected at most #{max} SQL queries, got #{count}"
    end

    # A small Rails-shaped app (two order screens, a machine-facing API, an
    # unused actor) for ScreenCatalog / ScreenImpactLocator / the LLM batch
    # pipeline, served from memory via FakeSnapshot — same file contents a
    # RepositorySnapshot would return, without a git repo.
    def screen_fixture_snapshot(overrides = {})
      FakeSnapshot.new(SCREEN_FIXTURE_FILES.merge(overrides))
    end

    SCREEN_FIXTURE_FILES = {
      "app/controllers/orders_controller.rb" => <<~RUBY,
        class OrdersController < ApplicationController
          # GET /orders
          def index
            @orders = Orders::List.call.orders
          end

          # GET /orders/new
          def new
          end

          # POST /orders
          def create
            actor = Orders::Create.result(params: order_params)
            render_success_json(actor)
          end

          private

          def order_params
            params.require(:order).permit(:qty)
          end
        end
      RUBY
      "app/controllers/api/machines_controller.rb" => <<~RUBY,
        class Api::MachinesController < ApplicationController
          # POST /api/machines/report
          def report
            Machines::Report.call(params:)
          end
        end
      RUBY
      "app/actors/orders/list.rb" => "class Orders::List < Actor\n  def call\n  end\nend\n",
      "app/actors/orders/create.rb" => "class Orders::Create < Actor\n  def call\n    Orders::Validate.call(order:)\n  end\nend\n",
      "app/actors/orders/validate.rb" => "class Orders::Validate < Actor\n  def call\n    check_qty\n  end\n\n  def check_qty\n  end\nend\n",
      "app/actors/machines/report.rb" => "class Machines::Report < Actor\n  def call\n  end\nend\n",
      "app/actors/orphan.rb" => "class Orphan < Actor\n  def call\n  end\nend\n",
      "app/views/layouts/_navbar.html.erb" => %(<%= link_to "訂單管理", orders_path %>\n),
      "app/views/orders/index.html.erb" => <<~ERB,
        <%= render "/layouts/navbar" %>
        <h1>訂單管理</h1>
        <%= link_to "新增訂單", new_order_path %>
        <%# 開發註解：這行不應被當成畫面文字 %>
        <order-search></order-search>
      ERB
      "app/views/orders/new.html.erb" => %(<h3>新增訂單&nbsp;<span>*為必填欄位</span></h3>\n<%= render "form" %>\n),
      "app/views/orders/_form.html.erb" => %(<div id="order-form"><order-form :token="x"></order-form></div>\n),
      "app/packs/src/javascripts/orders/OrderForm.vue" => <<~VUE,
        <script setup>
        import BaseInput from '@/src/vueComponent/BaseInput.vue'
        // 送出前檢查（開發註解）
        $.ajax({ url: '/orders', type: 'POST' })
        </script>
        <template>
          <label>數量</label><base-input />
          <button>送出</button>
        </template>
      VUE
      "app/packs/src/javascripts/orders/OrderSearch.vue" => "<template><button>搜尋</button></template>\n",
      "app/packs/src/vueComponent/BaseInput.vue" => "<template><input /></template>\n",
      "app/packs/src/javascripts/orders/form.js" => "import OrderForm from '@/src/javascripts/orders/OrderForm.vue'\n",
      "config/locales/zh-TW/model.yml" => <<~YAML,
        zh-TW:
          activerecord:
            models:
              order: 訂單
            attributes:
              order:
                qty: 數量
      YAML
      "db/migrate/20260101000000_add_qty_to_orders.rb" => "class AddQtyToOrders < ActiveRecord::Migration[7.1]\nend\n",
    }.freeze
  end
end

# In-memory stand-in for RepositorySnapshot ({ path => content }).
class FakeSnapshot
  def initialize(files)
    @files = files
  end

  def paths
    @files.keys
  end

  def read(path)
    @files[path]
  end

  def preload(_paths); end
end
