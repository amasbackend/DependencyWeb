# frozen_string_literal: true

class RouteParserService
  def parse(content)
    return [] if content.blank?

    content = content.to_s.dup.force_encoding("UTF-8")
    routes = []
    content.each_line do |line|
      line = line.strip
      next if line.start_with?("#") || line.blank?

      comment = line[/#\s*(.+)$/, 1]&.strip
      next if comment.blank?

      if (match = line.match(/(?:get|post|patch|put|delete)\s+["']([^"']+)["']/i))
        http_method = line[/\A(get|post|patch|put|delete)/i, 1]&.downcase
        routes << {
          route_path: match[1],
          route_comment: comment,
          http_method: http_method,
          entry_type: infer_entry_type(match[1], comment, http_method),
        }
      elsif (match = line.match(/resources\s+:(\w+)/))
        routes << { route_path: match[1], route_comment: comment, http_method: nil, resource: true, entry_type: "page" }
      end
    end

    routes
  end

  def comment_for_controller_action(routes, controller_path, action_name)
    controller_segment = controller_path.split("/").last&.singularize
    return nil if controller_segment.blank?

    routes.find do |route|
      path = route[:route_comment].to_s
      route[:route_path].to_s.include?(controller_segment) &&
        (action_name.blank? || path.present?)
    end&.dig(:route_comment)
  end

  def entry_type_for_controller_action(routes, controller_path, action_name)
    controller_segment = controller_path.split("/").last
    return infer_entry_type(action_name, nil, nil) if controller_segment.blank?

    matched = routes.find do |route|
      path = route[:route_path].to_s
      path.include?(controller_segment.singularize) || path.include?(controller_segment)
    end

    return matched[:entry_type] if matched&.dig(:entry_type).present?

    infer_entry_type(action_name, nil, nil)
  end

  private

  def infer_entry_type(route_path, comment, _http_method)
    combined = [route_path, comment].compact.join(" ").downcase
    return "pdf" if combined.include?("pdf")
    return "export" if combined.include?("export") || combined.include?("匯出")

    "page"
  end
end
