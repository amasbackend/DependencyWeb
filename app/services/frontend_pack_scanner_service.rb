# frozen_string_literal: true

class FrontendPackScannerService
  PACK_ROOTS = %w[app/packs app/javascript].freeze

  def initialize(github_service: GithubRepoService.new)
    @github = github_service
  end

  # @return [Hash{String => Array<String>}] controller_path => pack file paths
  def packs_by_controller_path(owner:, repo:, branch:)
    grouped = Hash.new { |h, k| h[k] = [] }

    PACK_ROOTS.each do |root|
      files = @github.get_directory_files(owner, repo, root, branch)
      files.each do |file|
        controller_path = controller_path_from_pack(file[:path])
        next if controller_path.blank?

        grouped[controller_path] << file[:path]
      end
    end

    grouped.transform_values(&:uniq)
  end

  def controller_path_from_pack(path)
    match = path.match(%r{(?:app/packs|app/javascript)/(?:src/)?javascripts/([^/]+/[^/]+)/})
    return match[1] if match

    nil
  end
end
