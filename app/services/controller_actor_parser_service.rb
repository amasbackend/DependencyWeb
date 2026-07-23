# frozen_string_literal: true

class ControllerActorParserService
  ACTOR_CALL_PATTERN = /([A-Z][A-Za-z0-9_:]*)\.(?:call|result)(?:!)?/.freeze
  PERMISSION_PATTERN = /permission_check\(\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']\s*\)/.freeze

  def parse_file(content, file_path:)
    controller_path = file_path_to_controller_path(file_path)
    channel = controller_path.start_with?("api/") ? "api" : "web"
    permissions = parse_permissions(content)

    entries = []
    content.scan(/def\s+(\w+)/) do |action_match|
      action_name = action_match[0]
      next if action_name.start_with?("_")

      method_body = extract_method_body(content, action_name)
      actors = method_body.scan(ACTOR_CALL_PATTERN).flatten.uniq
      perm = permissions[action_name] || permissions[:default]

      actors.each do |actor_name|
        entries << {
          controller_path: controller_path,
          controller_action: action_name,
          actor_name: actor_name,
          perm_module: perm&.first,
          perm_action: perm&.last,
          channel: channel,
          entry_type: infer_entry_type(action_name),
        }
      end
    end

    entries
  end

  private

  def file_path_to_controller_path(file_path)
    file_path
      .sub(%r{^app/controllers/}, "")
      .sub(/\.rb\z/, "")
      .sub(/_controller\z/, "")
  end

  def parse_permissions(content)
    perms = {}
    content.scan(/before_action\s+(?:->\s*\{\s*)?permission_check\(\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']\s*\).*?(?:only:\s*\[([^\]]+)\])?/m) do |mod, action, only|
      targets = if only.present?
                  only.scan(/:(\w+)/).flatten.map(&:to_s)
                else
                  [:default]
                end
      targets.each do |target|
        key = target == :default ? :default : target
        perms[key.to_sym] = [mod, action]
      end
    end
    perms
  end

  def extract_method_body(content, method_name)
    match = content.match(/def\s+#{Regexp.escape(method_name)}\b.*?(?=\n\s*def\s+|\z)/m)
    match ? match[0] : ""
  end

  def infer_entry_type(action_name)
    return "export" if action_name.include?("export")
    return "pdf" if action_name.include?("pdf")

    "page"
  end
end
