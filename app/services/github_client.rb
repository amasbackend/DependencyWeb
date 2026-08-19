# Shared Octokit client factory — avoids the duplicated raw Net::HTTP client
# construction that was one of DependencyWeb's confirmed architectural problems
# (see docs/architecture_plan.md §2). Every Actor that needs the GitHub API
# gets its client from here rather than building one itself.
class GithubClient
  def self.build
    Octokit::Client.new(access_token: GithubConfig.access_token)
  end
end
