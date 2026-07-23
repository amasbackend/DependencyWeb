# frozen_string_literal: true

module QaDisplayHelper
  def qa_view_mode
    params[:view] == "tech" ? "tech" : "qa"
  end

  def qa_model_label(company, model_name)
    labels = company.locale_metadata&.model_labels || {}
    key = model_name.to_s
    labels[key] || labels[key.underscore] || model_name
  end

  def qa_model_list(company, model_names)
    Array(model_names).map { |name| qa_model_label(company, name) }.join(", ")
  end

  def qa_column_labels(company, model_hint, columns)
    return safe_join_utf8(columns) if columns.blank?

    attribute_labels = company.locale_metadata&.attribute_labels || {}
    model_key = model_hint.to_s.underscore
    model_attrs = attribute_labels[model_key] || {}

    Array(columns).map do |col|
      col_key = col.to_s
      model_attrs[col_key] ||
        model_attrs[col_key.underscore] ||
        cross_model_attribute_label(attribute_labels, col_key) ||
        col
    end.join(", ")
  end

  def qa_entry_point_for(action_page, entry_points_by_action)
    entry_points_by_action[action_page.id]
  end

  def qa_management_page_label(company, management_page)
    return "" unless management_page

    name = management_page.name.to_s
    lm = company.locale_metadata
    lm&.menu_labels&.[](name).presence ||
      lm&.model_labels&.[](name).presence ||
      lm&.perm_module_labels&.[](name).presence ||
      name
  end

  def qa_menu_path(company, action_page, entry_points_by_action, ui_menus_by_controller)
    entry = qa_entry_point_for(action_page, entry_points_by_action)
    if entry&.ui_menu
      menu = entry.ui_menu
      module_part = menu.module_label.presence || menu.namespace.presence
      return [module_part, menu.menu_label].compact.join(" > ")
    end

    if entry&.controller_path.present?
      menu = ui_menus_by_controller[entry.controller_path]&.first
      if menu
        module_part = menu.module_label.presence || menu.namespace.presence
        return [module_part, menu.menu_label].compact.join(" > ")
      end
    end

    qa_management_page_label(company, action_page.management_page)
  end

  def qa_operation_label(company, action_page)
    labels = company.locale_metadata&.operation_type_labels || {}
    key = action_page.name.to_s.split("::").last&.underscore
    inferred = OperationTypeInfererService.infer(action_page.name, labels: labels)
    stored = action_page.operation_type.presence
    suffix = action_page.name.to_s.split("::").last

    # locale 有對應 key 時一律以 locale／Inferer 為準（避免舊庫殘留「查詢」蓋住列表／檢視）
    return inferred if key.present? && labels[key].present?
    return inferred if stored.blank? || stored == suffix

    stored
  end

  def qa_permission_label(company, entry)
    return "—" unless entry&.perm_module.present?

    lm = company.locale_metadata
    module_label = lm&.perm_module_labels&.[](entry.perm_module).presence || entry.perm_module
    action_label =
      if entry.perm_action.present?
        lm&.perm_action_labels&.[](entry.perm_action).presence || entry.perm_action
      end

    [module_label, action_label].compact.join(" / ")
  end

  def qa_entry_summary(entry)
    return "—" unless entry

    parts = [entry.controller_path, entry.controller_action].compact.join("#")
    parts = "#{entry.channel.upcase} #{parts}" if entry.channel == "api"
    parts
  end

  private

  def cross_model_attribute_label(attribute_labels, col_key)
    attribute_labels.each_value do |attrs|
      next unless attrs.is_a?(Hash)

      label = attrs[col_key] || attrs[col_key.underscore]
      return label if label.present?
    end
    nil
  end
end
