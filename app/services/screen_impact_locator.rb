# Traces every change in a PR to the operator screens (ScreenCatalog) that
# exercise it — deterministically, so the LLM is told "this change shows up on
# 品保檢驗管理 › 新增品檢檢驗回報" instead of having to guess from code names.
#
# A changed actor/model/concern is followed up its callers (by constant and
# method-name references in the code at the PR head, plus the controller hits
# Graphify's own impact items already found) until a controller action is
# reached; the action then maps to the screen that renders it or calls it. A
# changed view/Vue/partial maps to the screens built from it. Whatever can't
# reach a screen is still returned, bucketed by why (外部 API, 資料庫, 語系…),
# so every changed file is accounted for — nothing is silently dropped.
class ScreenImpactLocator
  Mapping = Struct.new(
    :ref, :changed_code_entity, :changed_file, :subject, :entry_actions, :screen_keys, :trace, :bucket,
    keyword_init: true,
  )

  BUCKET_LABELS = {
    "api" => "外部系統 API（非畫面操作）",
    "shared" => "共用程式／元件（影響多個畫面）",
    "database" => "資料庫結構／種子資料",
    "locale" => "語系文字",
    "background" => "排程／背景作業",
    "config" => "系統設定",
    "asset" => "圖檔／靜態資源",
    "dev_only" => "開發工具／測試檔（不影響操作）",
    "removed" => "已刪除的檔案",
    "unreferenced" => "目前程式中沒有任何呼叫端",
    "unknown" => "無法自動對應畫面",
  }.freeze

  FILE_BUCKETS = [
    [ %r{\A(?:spec|test)/|\A\.|\A(?:Gemfile|package\.json|yarn\.lock|babel\.config|postcss\.config|tailwind\.config)}, "dev_only" ],
    [ %r{\Adb/}, "database" ],
    [ %r{\Alib/tasks/|\Aapp/jobs/|\Aconfig/schedule}, "background" ],
    [ %r{\Aconfig/}, "config" ],
    [ %r{\Aapp/assets/|\Apublic/|\.(?:png|jpe?g|gif|svg|ico|pdf)\z}, "asset" ],
  ].freeze

  RUBY_CLASS_PATH = %r{\A(?:app/(?:models|controllers|actors|blueprints|helpers|jobs|mailers|services|serializers|policies|forms|queries|validators)/(?:concerns/)?|lib/(?!tasks/))(?<name>.+)\.rb\z}
  MODEL_PATH = %r{\Aapp/models/(?!concerns/)}
  CONTROLLER_PATH = %r{\Aapp/controllers/(?<controller_path>[a-z0-9_/]+)_controller\.rb\z}
  BEFORE_ACTION = /before_action\s+:(?<name>\w+)(?:\s*,\s*only:\s*(?:\[(?<list>[^\]]*)\]|:(?<one>\w+)))?/

  # Hops from a changed class up through intermediate callers (actor → actor →
  # controller); bounded like Impacts::MapCodeEntities's reverse BFS.
  MAX_HOPS = 4
  # A change reaching more screens than this is a cross-cutting/shared change
  # (a base controller helper, a shared component): reported once in the
  # shared group instead of being repeated inside every screen's batch.
  SHARED_SCREEN_LIMIT = 8
  # Method names too common to trace by name alone — fall back to the class.
  GENERIC_METHOD_NAMES = %w[call result find list create update destroy new index show edit initialize perform params].freeze

  def self.call(pull_request_analysis:, snapshot:, catalog:)
    new(pull_request_analysis, snapshot, catalog).call
  end

  def initialize(pull_request_analysis, snapshot, catalog)
    @pull_request_analysis = pull_request_analysis
    @snapshot = snapshot
    @catalog = catalog
  end

  def call
    snapshot.preload(source_paths)

    entities = pull_request_analysis.changed_code_entities.includes(:changed_file).order(:id).to_a
    entity_mappings = entities.each_with_index.map { |cce, i| map_entity(cce, "CHG-#{i + 1}") }

    covered_file_ids = entities.map(&:changed_file_id).to_set
    file_mappings = pull_request_analysis.changed_files.order(:id).reject { |f| covered_file_ids.include?(f.id) }
                                         .each_with_index.map { |file, i| map_file(file, "FILE-#{i + 1}") }

    entity_mappings + file_mappings
  end

  private

  attr_reader :pull_request_analysis, :snapshot, :catalog

  # --- changed classes/methods ---------------------------------------------

  def map_entity(cce, ref)
    subject = [ cce.class_name, cce.method_name ].compact_blank.join("#")
    actions = entry_actions_for(cce)
    graphify_entry_actions(cce).each { |action| actions[action] ||= [ subject, "（Graphify 依賴）", action_label(action) ] }

    screen_keys = actions.keys.flat_map { |action| catalog.screens_for_action(action).map(&:key) }.uniq
    screen_keys |= view_screens_using(cce.method_name) if cce.entity_type == "helper" || cce.entity_type == "concern"

    bucket = "unreferenced" if actions.empty? && screen_keys.empty? && cce.entity_type != "controller" &&
      referrers(constant_pattern(cce.class_name.to_s), exclude: own_paths(cce.class_name.to_s)).empty?
    build_mapping(ref, subject, actions, screen_keys, changed_code_entity: cce, changed_file: cce.changed_file, bucket: bucket)
  end

  # { "controller_path#action" => [trace…] }
  def entry_actions_for(cce)
    class_name = cce.class_name.to_s
    method_name = cce.method_name.presence
    return {} if class_name.blank?

    if cce.entity_type == "controller"
      controller_entry_actions(class_name, method_name)
    elsif cce.entity_type == "model"
      model_entry_actions(class_name, method_name)
    elsif cce.entity_type == "concern"
      # A mixed-in method is called bare (no receiver) by the including class;
      # fall back to "every class that includes the concern".
      by_name = method_name && !GENERIC_METHOD_NAMES.include?(method_name) ?
        method_referrer_actions(method_name, [ "#{class_name}##{method_name}" ], exclude: own_paths(class_name), bare: true) : {}
      by_name.presence || constant_referrer_actions(class_name, [ [ class_name, method_name ].compact.join("#") ])
    else
      constant_referrer_actions(class_name, [ [ class_name, method_name ].compact.join("#") ])
    end
  end

  def controller_entry_actions(class_name, method_name)
    controller_path = class_name.delete_suffix("Controller").underscore
    controller = catalog.controllers[controller_path]
    return {} unless controller

    actions =
      if method_name.nil? then controller[:actions]
      elsif controller[:actions].include?(method_name) then [ method_name ]
      else actions_matching(controller, /\b#{Regexp.escape(method_name)}\b/)
      end
    subject = [ class_name, method_name ].compact.join("#")
    actions.to_h { |a| [ "#{controller_path}##{a}", [ subject, action_label("#{controller_path}##{a}") ] ] }
  end

  # A model method is traced by name; a class-level model change (validation,
  # association, enum) by its own resource controller plus controllers that
  # use the model directly — not transitively through every actor touching
  # it, which for a core model would be most of the app.
  def model_entry_actions(class_name, method_name)
    if method_name && !GENERIC_METHOD_NAMES.include?(method_name)
      found = method_referrer_actions(method_name, [ "#{class_name}##{method_name}" ], exclude: own_paths(class_name))
      return found if found.any?
    end

    result = {}
    pattern = constant_pattern(class_name)
    catalog.controllers.each do |controller_path, controller|
      matched = actions_matching(controller, pattern)
      matched = controller[:actions] if matched.empty? && controller_path.split("/").last == class_name.demodulize.underscore.pluralize
      matched.each { |a| result["#{controller_path}##{a}"] ||= [ class_name, action_label("#{controller_path}##{a}") ] }
    end
    # Apps whose controllers only talk to actors never name the model in a
    # controller — then follow the actors that use it (a model used almost
    # everywhere ends up in the shared bucket via SHARED_SCREEN_LIMIT).
    result.presence || constant_referrer_actions(class_name, [ class_name ])
  end

  # Breadth-first up the "who references this constant" chain until
  # controllers are reached. Models are not traversed through (see above).
  def constant_referrer_actions(class_name, chain)
    result = {}
    queue = [ [ class_name, chain ] ]
    visited = Set[class_name]

    while (current, path = queue.shift)
      pattern = constant_pattern(current)
      referrers(pattern, exclude: own_paths(current)).each do |file|
        if (controller_path = file[CONTROLLER_PATH, :controller_path]) && (controller = catalog.controllers[controller_path])
          matched = actions_matching(controller, pattern)
          # `include SomeConcern` at class level: every action may use it.
          matched = controller[:actions] if matched.empty?
          matched.each { |a| result["#{controller_path}##{a}"] ||= path + [ action_label("#{controller_path}##{a}") ] }
        elsif (caller_class = constant_for(file)) && !visited.include?(caller_class) && !file.match?(MODEL_PATH) && path.size <= MAX_HOPS
          visited << caller_class
          queue << [ caller_class, path + [ caller_class ] ]
        end
      end
    end

    result
  end

  def method_referrer_actions(method_name, chain, exclude:, bare: false)
    pattern = bare ? /(?<!def )\b#{Regexp.escape(method_name)}\b/ : /(?:\.|&\.|:)#{Regexp.escape(method_name)}\b/
    result = {}
    referrers(pattern, exclude: exclude).each do |file|
      if (controller_path = file[CONTROLLER_PATH, :controller_path]) && (controller = catalog.controllers[controller_path])
        actions_matching(controller, pattern).each { |a| result["#{controller_path}##{a}"] ||= chain + [ action_label("#{controller_path}##{a}") ] }
      elsif (caller_class = constant_for(file)) && !file.match?(MODEL_PATH)
        constant_referrer_actions(caller_class, chain + [ caller_class ]).each { |k, v| result[k] ||= v }
      end
    end
    result
  end

  # Public actions whose body matches — directly, through a private helper
  # they call, or through a before_action filter that matches.
  def actions_matching(controller, pattern, depth = 0)
    methods = controller[:methods]
    direct = methods.reject(&:private).select { |m| m.body.match?(pattern) }.map(&:name)
    return direct.uniq if depth > 2

    via_private = methods.select(&:private).select { |m| m.body.match?(pattern) }.flat_map do |helper|
      actions_matching(controller, /\b#{Regexp.escape(helper.name)}\b/, depth + 1) + before_action_targets(controller, helper.name)
    end
    (direct + via_private).uniq & controller[:actions]
  end

  def before_action_targets(controller, filter_name)
    source = snapshot.read(controller[:path]).to_s
    source.scan(BEFORE_ACTION).flat_map do |name, list, one|
      next [] unless name == filter_name

      if list then list.scan(/:(\w+)/).flatten
      elsif one then [ one ]
      else controller[:actions]
      end
    end
  end

  # Controller-action ImpactItems Graphify's own reverse BFS already produced.
  def graphify_entry_actions(cce)
    graphify_actions_by_source[cce.id] || []
  end

  def graphify_actions_by_source
    @graphify_actions_by_source ||= pull_request_analysis.impact_items.includes(:code_entity)
      .select { |i| i.code_entity&.entity_type == "controller" && i.code_entity.method_name.present? }
      .group_by(&:source_changed_code_entity_id)
      .transform_values { |items| items.map { |i| "#{i.code_entity.class_name.delete_suffix('Controller').underscore}##{i.code_entity.method_name}" }.uniq }
  end

  def view_screens_using(method_name)
    return [] if method_name.blank?

    pattern = /\b#{Regexp.escape(method_name)}\b/
    catalog.all.select { |s| s.source_files.any? { |f| snapshot.read(f).to_s.match?(pattern) } }.map(&:key)
  end

  # --- changed files without a parsed class/method -------------------------

  def map_file(file, ref)
    path = file.file_path
    # tag.en.html.erb is the English variant of the tag.html.erb screen
    screens = (catalog.screens_with_file(path).presence || catalog.screens_with_file(path.sub(/\.[a-z]{2}(?:-[A-Za-z]+)?\.html\.erb\z/, ".html.erb"))).map(&:key)
    return build_mapping(ref, path, {}, screens, changed_file: file, trace_prefix: [ path ]) if screens.any?

    return map_deleted_file(file, ref) if file.change_type == "deleted"
    if (template_mapping = map_rendered_template(file, ref))
      return template_mapping
    end
    return build_mapping(ref, path, {}, [], changed_file: file, bucket: "shared") if path.include?("/entrypoints/")

    if path.match?(%r{\Aapp/helpers/.+\.rb\z})
      screens = changed_method_names(file).flat_map { |m| view_screens_using(m) }.uniq
      return build_mapping(ref, path, {}, screens, changed_file: file, trace_prefix: [ "#{path}（view helper）" ]) if screens.any?
    end

    if path.start_with?("config/locales/")
      actions = locale_entry_actions(file)
      screens = actions.keys.flat_map { |a| catalog.screens_for_action(a).map(&:key) }.uniq
      return build_mapping(ref, path, actions, screens, changed_file: file, bucket: screens.empty? ? "locale" : nil)
    end

    if (class_name = constant_for(path))
      actions = constant_referrer_actions(class_name, [ class_name ])
      screens = actions.keys.flat_map { |a| catalog.screens_for_action(a).map(&:key) }.uniq
      return build_mapping(ref, path, actions, screens, changed_file: file) if screens.any? || actions.any?
    end

    bucket = FILE_BUCKETS.find { |pattern, _| path.match?(pattern) }&.last || "unknown"
    build_mapping(ref, path, {}, [], changed_file: file, bucket: bucket)
  end

  # A deleted view/Vue file no longer exists at the PR head, so it can't be
  # found in the catalog; its directory still names the screens it served
  # (a deleted `_form` partial served new/edit).
  def map_deleted_file(file, ref)
    path = file.file_path
    controller_path = path[%r{\Aapp/views/(.+)/[^/]+\z}, 1] || path[%r{/javascripts/(.+)/[^/]+\z}, 1]
    screens = catalog.all.select { |s| s.controller_path == controller_path }
    screens = screens.select { |s| %w[new edit].include?(s.action) } if File.basename(path).start_with?("_form")
    keys = screens.map(&:key)
    fallback = FILE_BUCKETS.find { |pattern, _| path.match?(pattern) }&.last || "removed"
    build_mapping(ref, path, {}, keys, changed_file: file, bucket: keys.empty? ? fallback : nil,
      trace_prefix: [ "已刪除：#{path}（同目錄畫面）" ])
  end

  # A view template that isn't itself a screen (a printed tag or PDF a job
  # renders, or a partial of one) reaches operators through whatever code
  # renders it: trace the Ruby files that name the template.
  def map_rendered_template(file, ref)
    path = file.file_path
    return nil unless path.start_with?("app/views/") && path.end_with?(".html.erb")

    templates = template_names_for(path)
    actions = {}
    ruby_paths.each do |ruby|
      next unless templates.any? { |t| code_text(ruby).include?(t) }

      if (controller_path = ruby[CONTROLLER_PATH, :controller_path]) && (controller = catalog.controllers[controller_path])
        controller[:actions].each { |a| actions["#{controller_path}##{a}"] ||= [ "樣板 #{templates.first}", action_label("#{controller_path}##{a}") ] if code_text(ruby).include?(templates.first) }
      elsif (caller_class = constant_for(ruby))
        constant_referrer_actions(caller_class, [ "樣板 #{templates.first}", caller_class ]).each { |k, v| actions[k] ||= v }
      end
    end
    return nil if actions.empty?

    screens = actions.keys.flat_map { |a| catalog.screens_for_action(a).map(&:key) }.uniq
    build_mapping(ref, path, actions, screens, changed_file: file)
  end

  # "app/views/a/b/tag.en.html.erb" → ["a/b/tag"]; a partial → the templates
  # in the same directory that render it.
  def template_names_for(path)
    name = path.delete_prefix("app/views/").sub(/(?:\.[a-z]{2}(?:-[A-Za-z]+)?)?\.html\.erb\z/, "")
    dir, base = File.dirname(name), File.basename(name)
    return [ name ] unless base.start_with?("_")

    partial = base.delete_prefix("_")
    snapshot.paths.select { |p| p.start_with?("app/views/#{dir}/") && p.end_with?(".html.erb") && !File.basename(p).start_with?("_") }
            .select { |p| snapshot.read(p).to_s.match?(/render\s*\(?\s*(?:partial:\s*)?["'](?:\/?#{Regexp.escape(dir)}\/)?#{Regexp.escape(partial)}["']/) }
            .map { |p| p.delete_prefix("app/views/").sub(/(?:\.[a-z]{2}(?:-[A-Za-z]+)?)?\.html\.erb\z/, "") }.uniq
  end

  def changed_method_names(file)
    file.patch.to_s.scan(/^(?:@@.*@@\s*|[+\-]\s*)def\s+(?:self\.)?([a-z_][\w?!]*)/).flatten.uniq
  end

  # Maps changed locale keys (e.g. zh-TW.pms.examine_records.create.success,
  # zh-TW.actor.examine_record.create.failed) to the controller action or
  # class they belong to, by matching key segments against real paths.
  def locale_entry_actions(file)
    head = snapshot.read(file.file_path).to_s.lines
    added = DiffPatchParser.call(patch: file.patch).flat_map(&:lines).select { |l| l.type == "add" && l.new_line_no }
    result = {}

    added.each do |line|
      segments = locale_key_path(head, line.new_line_no - 1)
      locale_target(segments).each { |k, v| result[k] ||= [ "語系 #{segments.join('.')}" ] + v }
    end
    result
  end

  def locale_key_path(lines, index)
    stack = []
    lines[0..index].each do |line|
      match = line.match(/\A(?<indent>\s*)["']?(?<key>[\w\-]+)["']?:/)
      next unless match

      depth = match[:indent].size
      stack.pop while stack.any? && stack.last[0] >= depth
      stack << [ depth, match[:key] ]
    end
    stack.map(&:last)
  end

  def locale_target(segments)
    (0...segments.size).each do |i|
      (i...segments.size).each do |j|
        candidate = segments[i..j].join("/")
        next_segment = segments[j + 1]
        if (controller = catalog.controllers[candidate]) && controller[:actions].include?(next_segment)
          key = "#{candidate}##{next_segment}"
          return { key => [ action_label(key) ] }
        end
        class_name = candidate.camelize
        return model_entry_actions(class_name, nil) if path_set.include?("app/models/#{candidate}.rb")
        return constant_referrer_actions(class_name, [ class_name ]) if own_paths(class_name).any? && j > i
      end
    end
    {}
  end

  # --- shared ---------------------------------------------------------------

  def build_mapping(ref, subject, actions, screen_keys, changed_code_entity: nil, changed_file: nil, bucket: nil, trace_prefix: nil)
    bucket ||= if screen_keys.size > SHARED_SCREEN_LIMIT then "shared"
    elsif screen_keys.empty? then actions.any? ? "api" : "unknown"
    end

    trace = actions.values.first(3).map { |chain| chain.join(" → ") }
    trace = [ trace_prefix.join ] if trace.empty? && trace_prefix

    Mapping.new(
      ref: ref, changed_code_entity: changed_code_entity, changed_file: changed_file, subject: subject,
      entry_actions: actions.keys, screen_keys: screen_keys, trace: trace, bucket: bucket,
    )
  end

  def action_label(key)
    controller_path, action = key.split("#", 2)
    "#{controller_path.camelize}Controller##{action}"
  end

  def source_paths
    @source_paths ||= snapshot.paths.select { |p| (p.start_with?("app/") && p.end_with?(".rb", ".erb", ".vue", ".js")) || p.match?(%r{\Alib/(?!tasks/).+\.rb\z}) }
  end

  def ruby_paths
    @ruby_paths ||= source_paths.select { |p| p.end_with?(".rb") }
  end

  def path_set
    @path_set ||= snapshot.paths.to_set
  end

  def code_text(path)
    (@code_texts ||= {})[path] ||= snapshot.read(path).to_s.gsub(/^\s*#.*$/, "")
  end

  def referrers(pattern, exclude:)
    ruby_paths.reject { |p| exclude.include?(p) }.select { |p| code_text(p).match?(pattern) }
  end

  # `A6Pack::Input::Create` or top-level `::A6Pack::Input::Create`, but not
  # `Other::A6Pack::Input::Create` nor `A6Pack::Input::CreateBatch`.
  def constant_pattern(class_name)
    /(?<![\w:])(?:::)?#{Regexp.escape(class_name)}(?![\w]|::[A-Z])/
  end

  def constant_for(path)
    match = RUBY_CLASS_PATH.match(path)
    match && match[:name].camelize
  end

  def own_paths(class_name)
    (@own_paths ||= ruby_paths.group_by { |p| constant_for(p) })[class_name] || []
  end
end
