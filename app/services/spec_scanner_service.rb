# frozen_string_literal: true

class SpecScannerService
  def initialize(github_service: GithubRepoService.new)
    @github = github_service
  end

  def actor_names_with_specs(owner:, repo:, branch:)
    files = @github.get_directory_files(owner, repo, "spec/actors", branch)
    files.filter_map { |file| actor_name_from_spec_path(file[:path]) }.uniq
  end

  def actor_name_from_spec_path(path)
    match = path.match(%r{spec/actors/(.+)_spec\.rb$})
    return nil unless match

    match[1].split("/").map { |segment| segment.camelize }.join("::")
  end
end
