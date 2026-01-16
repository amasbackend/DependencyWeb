# frozen_string_literal: true

module CodeAnalysis
  class CollectModelClassesFromGithub < Actor
    input :owner
    input :repo
    input :branch, default: "main"

    output :model_classes

    def call
      self.model_classes = []

      github_service = GithubRepoService.new
      files = github_service.get_directory_files(owner, repo, "app/models", branch)

      files.each do |file_info|
        next unless file_info[:path].end_with?(".rb")

        file_content = github_service.get_file_content(owner, repo, file_info[:path], branch)
        next unless file_content

        content = file_content[:content]
        class_name = content[/class\s+([\w:]+)/, 1]
        model_classes << class_name if class_name
      end

      puts "發現的 Model Classes: #{model_classes.count} 個"
      puts "Model Classes: #{model_classes.join(', ')}"
    end
  end
end
