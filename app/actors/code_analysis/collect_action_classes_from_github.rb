# frozen_string_literal: true

module CodeAnalysis
  class CollectActionClassesFromGithub < Actor
    input :owner
    input :repo
    input :branch, default: "main"

    output :action_classes

    def call
      self.action_classes = []

      github_service = GithubRepoService.new
      files = github_service.get_directory_files(owner, repo, "app/actors", branch)

      files.each do |file_info|
        next unless file_info[:path].end_with?(".rb")

        file_content = github_service.get_file_content(owner, repo, file_info[:path], branch)
        next unless file_content

        content = file_content[:content]
        class_name = content[/class\s+([\w:]+)/, 1]
        action_classes << class_name if class_name
      end

      puts "發現的 Action Classes: #{action_classes.count} 個"
    end
  end
end
