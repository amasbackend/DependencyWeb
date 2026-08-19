# `uv tool install graphifyy` (see docs/setup.md) places the `graphify`
# binary under ~/.local/bin, which is only on PATH in interactive shells that
# source .bashrc/.profile — not guaranteed for however the app server or
# Solid Queue worker process was actually launched (systemd, Docker, etc.).
# Ensure it's reachable regardless, so GraphifyCli doesn't depend on the
# parent process's shell setup.
local_bin = File.join(Dir.home, ".local", "bin")
if Dir.exist?(local_bin) && !ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).include?(local_bin)
  ENV["PATH"] = "#{local_bin}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
end
