# frozen_string_literal: true

class NavbarParserService
  ENTRY_PATTERN = /
    \{
    (?<body>.*?)
    \}
  /mx.freeze

  def parse(content, source_path: nil)
    return [] if content.blank?

    namespace = extract_namespace(source_path)
    menus = []

    content.scan(ENTRY_PATTERN) do
      body = Regexp.last_match[:body]
      menu_label = extract_value(body, /(?:name|text):\s*["']([^"']+)["']/)
      controller_path = extract_value(body, /controller_path:\s*["']([^"']+)["']/)
      perm_module = extract_value(body, /perm_module:\s*["']([^"']+)["']/)
      actions = extract_actions(body)

      next if menu_label.blank? || controller_path.blank?

      menus << {
        namespace: namespace,
        menu_label: menu_label,
        controller_path: controller_path,
        perm_module: perm_module,
        actions: actions,
      }
    end

    menus.uniq { |m| [m[:controller_path], m[:menu_label]] }
  end

  private

  def extract_namespace(source_path)
    return "" if source_path.blank?

    # app/views/pms/_navbar.html.erb -> pms
    match = source_path.match(%r{app/views/([^/]+)/})
    match ? match[1] : ""
  end

  def extract_value(body, pattern)
    body.match(pattern)&.captures&.first
  end

  def extract_actions(body)
    match = body.match(/actions:\s*%w\[(.*?)\]/)
    return [] unless match

    match[1].split(/\s+/).reject(&:blank?)
  end
end
