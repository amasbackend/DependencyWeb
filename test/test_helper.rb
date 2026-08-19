ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

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
  end
end
