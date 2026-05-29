# GitHub REST API：優先 classic PAT（credentials.github_classic_token），未設定則沿用 github_access_token
GITHUB_ACCESS_TOKEN = Rails.application.credentials[:github_access_token].freeze
GITHUB_CLASSIC_TOKEN = Rails.application.credentials[:github_classic_token].freeze
GITHUB_API_TOKEN = (GITHUB_CLASSIC_TOKEN.presence || GITHUB_ACCESS_TOKEN).freeze