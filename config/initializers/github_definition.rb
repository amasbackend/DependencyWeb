# GitHub-related configuration. Token access is lazy (evaluated only when an
# Actor actually calls it) so boot/migrate/test runs never crash just because
# GITHUB_ACCESS_TOKEN isn't set yet (see docs/architecture_plan.md §16).
GITHUB_API_BASE_URL = "https://api.github.com".freeze
REPOSITORY_ROOT = ENV.fetch("REPOSITORY_ROOT", Rails.root.join("storage", "repositories").to_s).freeze

# Mutable override point for tests (RepositoryPaths#repository_root reads this
# first, falling back to the frozen REPOSITORY_ROOT above) — lets tests point
# git operations at a tmpdir instead of writing into real storage/repositories.
Rails.application.config.x.repository_root = nil

module GithubConfig
  def self.access_token
    ENV.fetch("GITHUB_ACCESS_TOKEN")
  end
end
