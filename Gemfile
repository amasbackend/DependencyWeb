# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.4"

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem "audited"
gem "bcrypt", "~> 3.1.7"
gem "blueprinter"
gem "bootsnap", ">= 1.1.0", require: false
gem "bootstrap-sass"
gem "calc"
gem "caxlsx"
gem "combine_pdf"
gem "enumerize"
gem "exception_notification"
gem "faraday"
gem "foreman"
gem "i18n-js", "~> 3.9"
gem "jbuilder", "~> 2.5"
gem "line-bot-api"
gem "mysql2"
gem "pagy", "~> 6.5.0" # 目前參數設置使用的穩定版本 不可變更
gem "puma", "~> 5.0"
gem "rails", "~> 7.1.2"
gem "rails-i18n"
gem "roo"
gem "sass-rails", "~> 5.0"
gem "service_actor"
gem "service_actor-rails"
gem "slack-notifier"
gem "time_difference"
gem "turbo-rails"
gem "twsms2", "~> 1.3"
gem "uglifier", ">= 1.3.0"
gem "vite_rails"
gem "whenever", require: false

group :development, :test do
  gem "annotate"
  gem "bullet"
  gem "byebug", platforms: %i[mri mingw x64_mingw]
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "pry-rails"
  gem "rails-controller-testing"
  gem "rspec-rails"
  gem "rubocop", require: false
  gem "rubocop-erb", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
  gem "shoulda-matchers"
  gem "simplecov"
end

group :development do
  gem "better_errors"
  gem "brakeman"
  gem "listen"
  gem "rails_best_practices"
  gem "reek"
  gem "web-console"
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

gem "tailwindcss-rails", "~> 4.2"
