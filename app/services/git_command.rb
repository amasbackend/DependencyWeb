require "open3"

# Thin wrapper around the `git` CLI. Every call passes arguments as a Ruby
# array to Open3.capture3, which execs the binary directly with no shell
# involved — string interpolation into a shell command line (the exact
# command-injection pattern flagged in docs/architecture_plan.md §16) is not
# possible through this interface.
class GitCommand
  class Error < StandardError; end

  ASKPASS_SCRIPT = Rails.root.join("bin", "git_askpass").to_s

  def self.run(*args, git_dir: nil, env: {})
    full_args = git_dir ? [ "--git-dir=#{git_dir}", *args ] : args
    stdout, stderr, status = Open3.capture3(env, "git", *full_args)
    raise Error, stderr.presence || "git #{args.join(' ')} failed" unless status.success?

    stdout
  end

  # Injects the GitHub token via GIT_ASKPASS (bin/git_askpass) rather than the
  # clone URL or a CLI argument — an authenticated URL would persist into the
  # resulting repo's .git/config (explicitly prohibited, §3), and a token in
  # argv would be visible to other users via `ps aux` for the duration of the
  # process. GIT_ASKPASS_TOKEN, like every env var here, is only readable via
  # /proc/<pid>/environ by the same user or root.
  #
  # An earlier version used GIT_CONFIG_COUNT/KEY_0/VALUE_0 to inject an
  # http.extraheader — that env-var-based config mechanism was only added in
  # Git 2.31, and silently does nothing on this host's Git 2.25.1, which then
  # falls back to an interactive credential prompt that fails outright since
  # GIT_TERMINAL_PROMPT=0 disables prompting. Discovered via a real end-to-end
  # clone of a private repo, not a unit test (fixtures are always public/local
  # and never exercised the auth path at all). GIT_ASKPASS works on any Git
  # version, so it doesn't have this problem.
  def self.auth_env
    {
      "GIT_TERMINAL_PROMPT" => "0",
      "GIT_ASKPASS" => ASKPASS_SCRIPT,
      "GIT_ASKPASS_TOKEN" => GithubConfig.access_token,
    }
  end
end
