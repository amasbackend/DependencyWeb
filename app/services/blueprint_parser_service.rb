# frozen_string_literal: true

class BlueprintParserService
  REFERENCE_PATTERN = /([A-Z][A-Za-z0-9_:]*Blueprint)\.(?:render_as_hash|render|prepare)/.freeze

  def parse(content)
    return [] if content.blank?

    content.scan(REFERENCE_PATTERN).flatten.uniq.sort
  end

  def blueprint_name_from_file_path(file_path)
    # app/blueprints/work_order/info_blueprint.rb => WorkOrder::InfoBlueprint
    relative = file_path.sub(%r{^app/blueprints/}, "").sub(/\.rb\z/, "")
    parts = relative.split("/")
    return nil if parts.empty?

    class_part = parts.pop.camelize
    namespace = parts.map(&:camelize).join("::")
    namespace.present? ? "#{namespace}::#{class_part}" : class_part
  end
end
