# The operator-facing screens of a Rails app (one per controller action that
# renders a view), built deterministically from the code at one commit — the
# missing link between "which code changed" and "which screen should an
# operator open to test it". For each screen it collects what an operator
# actually sees (menu name, page title, every Chinese label in the view and
# the Vue components it mounts) and which backend endpoints the page calls,
# so ScreenImpactLocator can route a changed actor/model/controller to the
# screens that exercise it, and the LLM can phrase steps using real labels
# instead of guessing button names.
#
# Convention-driven (Rails view paths, Zeitwerk naming, Vue mounted either as
# `<kebab-tag>` components or via `createApp(...)` onto an element id,
# `# GET /path` comments above actions, i18n `t('key')` calls resolved
# through the app's own zh-TW locale files) — anything that doesn't follow
# those conventions simply isn't catalogued, it never raises.
class ScreenCatalog
  Screen = Struct.new(
    :key, :controller_path, :action, :controller_class, :url, :menu_name, :title,
    :labels, :source_files, :endpoints, keyword_init: true,
  ) do
    def display_name
      [ menu_name, title ].compact_blank.uniq.join(" › ").presence || key
    end

    def page_path
      "#{display_name}（#{url}）"
    end
  end

  VIEW_PATH = %r{\Aapp/views/(?<controller_path>[a-z0-9_/]+)/(?<action>[a-z0-9_]+)\.html\.erb\z}
  CONTROLLER_PATH = %r{\Aapp/controllers/(?<controller_path>[a-z0-9_/]+)_controller\.rb\z}
  FRONTEND_PATH = %r{\Aapp/(?:packs|javascript)/.+\.(?:vue|js)\z}
  VUE_TAG = /<(?<tag>[a-z][a-z0-9]*(?:-[a-z0-9]+)+)[\s>\/]/
  IMPORT = /import\s+(?:\w+|\{[^}]*\})\s+from\s+["'](?<path>[^"']+)["']/
  IMPORT_NAMED = /import\s+(?<name>\w+)\s+from\s+["'](?<path>[^"']+)["']/
  ELEMENT_ID = /\bid=["'](?<id>[A-Za-z][\w\-]*)/
  # document.getElementById('x') / querySelector('#x') / querySelectorAll('[id^="x"]')
  MOUNT_TARGET = /getElementById\(\s*["'`](?<id1>[\w\-]+)["'`]|querySelector(?:All)?\(\s*["'`]#(?<id2>[\w\-]+)["'`]|querySelectorAll\(\s*["'`]\[id\^=["']?(?<prefix>[\w\-]+)/
  # A mount script that says which pages it runs on, e.g.
  # pageWatcher({ controller: 'production_management/stocks', action: ['index', 'show'] })
  DECLARED_PAGES = /controller:\s*["'](?<controller>[\w\/]+)["']\s*,\s*action:\s*(?:\[(?<list>[^\]]*)\]|["'](?<one>\w+)["'])/
  # t('a.b') / I18n.t('a.b') / i18n.t('a.b') / $t('a.b'), and Rails' relative t('.b')
  I18N_CALL = /(?:(?:I18n|i18n)\.t|(?<![\w.$])\$?t)\(\s*["'`](?<key>\.?[A-Za-z_][\w.\-]*)["'`][^)\n]*\)/
  TEMPLATE_RENDER = /render\s*\(?\s*(?:template:\s*)?["']\/?(?<template>[\w]+\/[\w\/]+)["']/
  Mount = Struct.new(:id, :prefix, :files, :script, :declared, keyword_init: true)
  URL_LITERAL = %r{["'`](?<url>/[A-Za-z0-9_\-/:.${}]+)(?:\?[^"'`]*)?["'`]}
  # "工單管理", pms_work_orders_path — a Chinese link text paired with a
  # route helper, whether in link_to or a navbar `{ name:, path: }` hash.
  LINK_TEXT = /["'](?<text>[^"'\n]*\p{Han}[^"'\n]*)["']\s*,\s*(?:path:\s*)?(?<helper>[a-z][a-z0-9_]*)_(?:path|url)\b/
  MENU_FILE = /navbar|header|menu|sidebar/
  # "回人員列表" / "返回製程列表" — a back button's text names the list, minus the "back"
  BACK_LINK_PREFIX = /\A(?:返回|回到|回)(?=.*(?:列表|首頁|頁)\z)/
  PAGE_NAME_HINT = /看板|管理|查詢|設定|清單|列表|報表/
  HEADING = %r{<h[1-3][^>]*>(?<inner>.*?)</h[1-3]>}m
  LABEL = /[^<>"'`{}\n=;()\[\]|]*\p{Han}[^<>"'`{}\n=;()\[\]|]*/
  MAX_LABELS = 120

  # A Vue component mounted by more screens than this is a shared building
  # block (input, dialog, alert…) — its labels say nothing about any one
  # screen, so they're left out of each screen's label list.
  SHARED_COMPONENT_THRESHOLD = 6

  def self.call(snapshot:)
    new(snapshot).call
  end

  def initialize(snapshot)
    @snapshot = snapshot
  end

  def call
    snapshot.preload(snapshot.paths.select { |p| p.match?(VIEW_PATH) || p.match?(CONTROLLER_PATH) || p.match?(FRONTEND_PATH) || p.end_with?(".html.erb") })

    screens = screen_views.filter_map { |key, path| build_screen(key, path) }
    shared = shared_components(screens)

    screens.each do |screen|
      # Menu partials (navbar) are kept as source files — a navbar change does
      # affect every screen — but their link texts aren't this screen's labels.
      label_files = screen.source_files.reject { |f| shared.include?(f) || File.basename(f).match?(MENU_FILE) }
      entry_label = entry_link_texts[screen.key]
      screen.labels = [ entry_label, *label_files.flat_map { |f| self.class.labels_in(source(f)) } ].compact.uniq.first(MAX_LABELS)
      # No menu link and no heading (e.g. a kiosk board): name it by its most
      # page-title-like label rather than a generic "列表".
      if screen.menu_name.nil? && ACTION_TITLES.value?(screen.title)
        screen.title = screen.labels.select { |l| l.length <= 12 && l.match?(PAGE_NAME_HINT) }.min_by(&:length) || screen.title
      end
      screen.source_files += entry_scripts_for(screen, shared)
    end

    Result.new(screens.index_by(&:key), controllers, shared, i18n_stats)
  end

  # Chinese-text runs an operator would see (button/field/heading/message
  # text), with comments stripped first so developer notes don't masquerade
  # as on-screen labels.
  def self.labels_in(source)
    cleaned = CGI.unescapeHTML(source.to_s.gsub("&nbsp;", " "))
      .gsub(/<!--.*?-->/m, " ").gsub(/<%#.*?%>/m, " ").gsub(%r{/\*.*?\*/}m, " ")
      .gsub(%r{(?<![:"'\w])//[^\n]*}, " ").gsub(/^\s*#[^\n]*/, " ")
    cleaned.scan(LABEL).map { |s| s.squish.sub(/\A[:,.\s]+/, "").sub(/\s*[:,]\s*[A-Za-z_$][\w.$()]*,?\z/, "").strip }
           .select { |s| s.length.between?(1, 40) }.uniq
  end

  class Result
    attr_reader :screens, :controllers, :shared_components, :i18n_stats

    def initialize(screens, controllers, shared_components, i18n_stats = {})
      @screens = screens
      @controllers = controllers
      @shared_components = shared_components
      @i18n_stats = i18n_stats
    end

    def [](key)
      screens[key]
    end

    def all
      screens.values
    end

    # Screens whose pages call the given "controller_path#action" endpoint,
    # or (for a non-GET action with no view of its own) the screen Rails
    # convention says submits to it.
    def screens_for_action(key)
      controller_path, action = key.split("#", 2)
      direct = [ screens[key] ].compact + all.select { |s| s.endpoints.include?(key) }
      conventional = CONVENTIONAL_SCREENS.fetch(action, []).filter_map { |a| screens["#{controller_path}##{a}"] }
      (direct + conventional).uniq(&:key)
    end

    def screens_with_file(path)
      all.select { |s| s.source_files.include?(path) }
    end

    CONVENTIONAL_SCREENS = {
      "create" => %w[new], "update" => %w[edit], "destroy" => %w[index show],
    }.freeze
  end

  private

  attr_reader :snapshot

  # "controller_path#action" => view template: each action's own view, plus
  # actions that explicitly render another controller's template
  # (`render "production_management/vibration_inspections/tag"`).
  def screen_views
    own = snapshot.paths.each_with_object({}) do |path, views|
      match = VIEW_PATH.match(path)
      next unless match && !match[:action].start_with?("_") && controllers.key?(match[:controller_path])

      views["#{match[:controller_path]}##{match[:action]}"] = path
    end

    controllers.each do |controller_path, controller|
      controller[:methods].reject(&:private).each do |method|
        template = method.body[TEMPLATE_RENDER, :template]
        path = template && "app/views/#{template}.html.erb"
        own["#{controller_path}##{method.name}"] ||= path if path && path_set.include?(path) && !File.basename(path).start_with?("_")
      end
    end
    own
  end

  ACTION_TITLES = {
    "index" => "列表", "new" => "新增", "edit" => "編輯", "show" => "詳細資訊", "show_pdf" => "PDF 檢視", "export_pdf" => "匯出 PDF",
  }.freeze

  def build_screen(key, view_path)
    controller_path, action = key.split("#", 2)
    controller = controllers.fetch(controller_path)
    partials = rendered_partials(view_path)
    view = [ view_path, *partials ].map { |p| source(p) }.join("\n")
    mount_scripts, vue_files = mounted_frontend_files(view, key, controller_path)

    Screen.new(
      key: key,
      controller_path: controller_path,
      action: action,
      controller_class: controller[:class_name],
      url: controller[:urls][action] || conventional_url(controller_path, action),
      # An operator reaches new/edit/show from the module's list page, so a
      # screen with no menu link of its own carries its index's menu name.
      menu_name: menu_links["#{controller_path}##{action}"] || menu_links["#{controller_path}#index"] || entry_link_texts["#{controller_path}#index"],
      title: heading(view) || ACTION_TITLES[action],
      source_files: [ view_path, *partials, *mount_scripts, *vue_files ].uniq,
      endpoints: endpoints_in([ view, *vue_files.reject { |f| widely_imported.include?(f) }.map { |f| snapshot.read(f) } ]),
    )
  end

  RENDER_CALL = /render\s*\(?\s*(?:partial:\s*)?["'](?<name>[\w\/]+)["']/

  # `render "form"` / `render "/pms/navbar"` partials, followed a few levels
  # deep — the new/edit pages typically keep their whole form in `_form`.
  def rendered_partials(view_path, depth = 0)
    return [] if depth > 3

    dir = File.dirname(view_path)
    snapshot.read(view_path).to_s.scan(RENDER_CALL).flatten.flat_map do |name|
      partial = name.include?("/") ? "app/views/#{File.dirname(name.delete_prefix('/'))}/_#{File.basename(name)}.html.erb" : "#{dir}/_#{name}.html.erb"
      next [] unless path_set.include?(partial)

      [ partial, *rendered_partials(partial, depth + 1) ]
    end.uniq
  end

  # controller_path => { class_name:, urls: { action => url }, actions: [...], methods: [RubySourceMethods::Definition] }
  def controllers
    @controllers ||= snapshot.paths.each_with_object({}) do |path, hash|
      match = CONTROLLER_PATH.match(path)
      next unless match

      methods = RubySourceMethods.call(snapshot.read(path))
      public_methods = methods.reject(&:private)
      hash[match[:controller_path]] = {
        path: path,
        class_name: "#{match[:controller_path].camelize}Controller",
        urls: public_methods.select(&:route_comment).to_h { |m| [ m.name, m.route_comment ] },
        actions: public_methods.map(&:name),
        methods: methods,
      }
    end
  end

  def conventional_url(controller_path, action)
    base = "/#{controller_path}"
    case action
    when "index" then base
    when "new" then "#{base}/new"
    when "show" then "#{base}/:id"
    when "edit" then "#{base}/:id/edit"
    else "#{base}/#{action}"
    end
  end

  def heading(view)
    match = HEADING.match(view)
    return nil unless match

    # "新增工單 *為必填欄位" — drop the required-field hint that shares the heading.
    inner = match[:inner].gsub(/<%=?|-?%>/, " ").gsub(/<[^>]+>/, " ")
    self.class.labels_in(inner).first&.split(/\s+\*/)&.first
  end

  # The frontend a page runs: Vue mounted as <work-order-new-form> tags, or
  # by a script's createApp(...) onto an element id the page contains — then
  # every frontend file those (transitively) import. Returns [mount scripts,
  # Vue/JS files].
  def mounted_frontend_files(view, key, controller_path)
    tag_roots = view.scan(VUE_TAG).flatten.uniq.filter_map { |tag| find_vue(tag.split("-").map(&:capitalize).join, controller_path) }
    ids = view.scan(ELEMENT_ID).flatten.uniq
    id_mounts = mounts.select do |m|
      (m.declared.nil? || m.declared.include?(key)) &&
        (m.id ? ids.include?(m.id) : ids.any? { |id| id.start_with?(m.prefix) })
    end

    seen = []
    queue = tag_roots + id_mounts.flat_map(&:files)
    while (file = queue.shift)
      next if seen.include?(file)

      seen << file
      snapshot.read(file).to_s.scan(IMPORT).flatten.each do |import|
        resolved = resolve_import(import, file)
        queue << resolved if resolved&.match?(FRONTEND_PATH)
      end
    end
    [ id_mounts.map(&:script).uniq, seen ]
  end

  # Every createApp(...) mount in the frontend scripts, keyed by the element
  # id (or id prefix) it mounts onto. Mounts of only widely shared components
  # (an alert box on every page) are skipped — they say nothing about which
  # page a script belongs to.
  def mounts
    @mounts ||= frontend_scripts.flat_map do |script|
      text = snapshot.read(script).to_s
      imports = text.scan(IMPORT_NAMED).to_h { |name, path| [ name, resolve_import(path, script) ] }.compact
      declared = declared_pages(text)
      targets = text.enum_for(:scan, MOUNT_TARGET).map { Regexp.last_match }

      targets.each_with_index.filter_map do |target, i|
        window = text[target.begin(0)...(targets[i + 1]&.begin(0) || text.size)].first(2_000)
        names = window.scan(/createApp\(\s*([A-Z]\w*)/).flatten +
                window.scan(/components:\s*\{([^}]*)\}/).flatten.flat_map { |list| list.scan(/[A-Z]\w*/) }
        files = names.filter_map { |name| imports[name] }.select { |f| f.end_with?(".vue") }.uniq
        next if files.empty? || files.all? { |f| widely_imported.include?(f) }

        Mount.new(id: target[:id1] || target[:id2], prefix: target[:prefix], files: files, script: script, declared: declared)
      end
    end
  end

  def declared_pages(text)
    pages = text.scan(DECLARED_PAGES).flat_map do |controller, list, one|
      actions = list ? list.scan(/["'](\w+)["']/).flatten : [ one ]
      actions.map { |action| "#{controller}##{action}" }
    end
    pages.presence&.to_set
  end

  def find_vue(component_name, controller_path)
    candidates = vue_files_by_name[component_name] || []
    resource = controller_path.split("/").last
    candidates.find { |f| f.include?("/#{resource}/") } || candidates.first
  end

  def vue_files_by_name
    @vue_files_by_name ||= snapshot.paths.select { |p| p.end_with?(".vue") }.group_by { |p| File.basename(p, ".vue") }
  end

  def resolve_import(import, from_file)
    candidates =
      if import.start_with?("@/")
        [ "app/packs/#{import.delete_prefix('@/')}", "app/javascript/#{import.delete_prefix('@/')}" ]
      elsif import.start_with?(".")
        [ File.expand_path(import, "/#{File.dirname(from_file)}").delete_prefix("/") ]
      else
        []
      end
    candidates.find { |c| path_set.include?(c) }
  end

  def path_set
    @path_set ||= snapshot.paths.to_set
  end

  # The mount scripts (e.g. pms/work_orders/form.js) that import a screen's
  # top-level Vue component — so a changed mount script also maps back.
  def entry_scripts_for(screen, shared)
    vue = screen.source_files.select { |f| f.end_with?(".vue") && !shared.include?(f) }
    return [] if vue.empty?

    frontend_scripts.select do |script|
      snapshot.read(script).to_s.scan(IMPORT).flatten.any? { |import| vue.include?(resolve_import(import, script)) }
    end
  end

  # Frontend files mounted by many screens or imported by many other
  # frontend files (BaseAlert, BaseSelect, a format helper…).
  def shared_components(screens)
    mounted = screens.flat_map { |s| s.source_files.select { |f| f.match?(FRONTEND_PATH) } }.tally
    (widely_imported + mounted.select { |_, count| count > SHARED_COMPONENT_THRESHOLD }.keys).to_set
  end

  def widely_imported
    @widely_imported ||= snapshot.paths.select { |p| p.match?(FRONTEND_PATH) }.flat_map do |file|
      snapshot.read(file).to_s.scan(IMPORT).flatten.filter_map { |import| resolve_import(import, file) }.uniq
    end.tally.select { |_, count| count > SHARED_COMPONENT_THRESHOLD }.keys.to_set
  end

  def frontend_scripts
    @frontend_scripts ||= snapshot.paths.select { |p| p.match?(FRONTEND_PATH) && p.end_with?(".js") }
  end

  # "controller_path#action" endpoints a page calls — URL literals in its
  # view/Vue code matched against every controller action's route comment.
  def endpoints_in(sources)
    urls = sources.flat_map { |s| s.to_s.scan(URL_LITERAL).flatten }
                  .map { |u| u.gsub(/\$\{[^}]*\}/, ":id").chomp("/") }.uniq
    urls.flat_map { |url| route_table.select { |pattern, _| url_matches?(url, pattern) }.values.flatten }.uniq
  end

  def route_table
    @route_table ||= controllers.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(controller_path, controller), table|
      controller[:actions].each do |action|
        table[controller[:urls][action] || conventional_url(controller_path, action)] << "#{controller_path}##{action}"
      end
    end
  end

  def url_matches?(url, pattern)
    a = url.split("/")
    b = pattern.split("/")
    a.size == b.size && a.zip(b).all? { |x, y| x == y || x.start_with?(":") || y.start_with?(":") }
  end

  # "controller_path#action" => the Chinese link text pointing at it from a
  # navbar/menu-like file — the name an operator navigates by.
  def menu_links
    link_texts.first
  end

  # Same, from any other page — the button an operator clicks to get there
  # (e.g. "新增預生產工單" on the list page leading to the new screen).
  def entry_link_texts
    link_texts.last
  end

  def link_texts
    @link_texts ||= begin
      menu = {}
      other = {}
      snapshot.paths.select { |p| p.end_with?(".html.erb", ".vue", ".js") && p.start_with?("app/") }.each do |path|
        target = File.basename(path).match?(MENU_FILE) ? menu : other
        source(path).scan(LINK_TEXT).each do |text, helper|
          key = helper_index[helper]
          target[key] ||= text.squish.sub(BACK_LINK_PREFIX, "") if key
        end
      end
      [ menu, other ]
    end
  end

  # File content with every i18n call it makes replaced by the zh-TW text it
  # renders (`t('module_name.stock')` → `"庫存查詢"`), so screens whose text
  # lives in locale files get real labels too. Unresolvable keys are left
  # as-is (and counted in i18n_stats).
  def source(path)
    (@sources ||= {})[path] ||= resolve_constants(snapshot.read(path).to_s).gsub(I18N_CALL) do |call|
      key = Regexp.last_match[:key]
      key = "#{relative_i18n_scope(path)}#{key}" if key.start_with?(".")
      i18n_keys << key
      text = translations[key]
      text.is_a?(String) ? text.inspect : call
    end
  end

  # Text built from app constants — "#{WORKAREA[:a1_order]} 工單列表" or
  # <%= WORKAREA[:a1_order] %> — with the constant's value substituted, so it
  # reads "原料加工 工單列表" instead of leaking Ruby into labels and names.
  CONSTANT_INTERPOLATION = /\#\{\s*(?<name>[A-Z][A-Z0-9_]*)(?:\[\s*(?::(?<sym>\w+)|["'](?<str>[^"']+)["']|(?<num>\d+))\s*\])?\s*\}/
  CONSTANT_LOOKUP = /(?<![\w:#])(?<name>[A-Z][A-Z0-9_]*)\[\s*(?::(?<sym>\w+)|["'](?<str>[^"']+)["']|(?<num>\d+))\s*\]/

  def resolve_constants(text)
    return text if string_constants.empty?

    text.gsub(CONSTANT_INTERPOLATION) { constant_value(Regexp.last_match) || Regexp.last_match[0] }
        .gsub(CONSTANT_LOOKUP) { (value = constant_value(Regexp.last_match)) ? value.inspect : Regexp.last_match[0] }
  end

  def constant_value(match)
    value = string_constants[match[:name]]
    key = match[:sym] || match[:str] || match[:num]
    value = value.is_a?(Hash) ? value[key] : (key ? nil : value)
    value.is_a?(String) ? value : nil
  end

  # NAME = "text" and NAME = { key: "text", "key" => "text", 1 => "text" }
  # from config/initializers — the app-wide label constants views use.
  def string_constants
    @string_constants ||= snapshot.paths.select { |p| p.start_with?("config/initializers/") && p.end_with?(".rb") }.each_with_object({}) do |path, table|
      text = snapshot.read(path).to_s
      text.scan(/^([A-Z][A-Z0-9_]*)\s*=\s*["']([^"'\n]*)["']/) { |name, value| table[name] = value }
      text.scan(/^([A-Z][A-Z0-9_]*)\s*=\s*\{(.*?)^\}/m) do |name, body|
        pairs = body.scan(/(?:(\w+):|["'](\w+)["']\s*=>|(\d+)\s*=>)\s*["']([^"'\n]*)["']/)
        table[name] = pairs.to_h { |sym, str, num, value| [ sym || str || num, value ] } if pairs.any?
      end
    end
  end

  # Rails lazy lookup: t('.title') in app/views/a/b/_form.html.erb is a.b.form.title
  def relative_i18n_scope(path)
    path.delete_prefix("app/views/").sub(/\.html\.erb\z/, "").split("/").map { |part| part.delete_prefix("_") }.join(".")
  end

  def i18n_keys
    @i18n_keys ||= Set.new
  end

  def i18n_stats
    { referenced: i18n_keys.size, resolved: i18n_keys.count { |k| translations[k].is_a?(String) } }
  end

  # Flattened "a.b.c" => "文字" from the app's zh-TW locale files.
  def translations
    @translations ||= snapshot.paths.select { |p| p.start_with?("config/locales/") && p.end_with?(".yml") && p.include?("zh-TW") }
      .each_with_object({}) do |path, table|
        doc = YAML.safe_load(snapshot.read(path).to_s, aliases: true, permitted_classes: [ Symbol ]) rescue nil
        flatten_locale(doc["zh-TW"], nil, table) if doc.is_a?(Hash) && doc["zh-TW"].is_a?(Hash)
      end
  end

  def flatten_locale(node, prefix, table)
    node.each do |key, value|
      full = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flatten_locale(value, full, table) : table[full] = value
    end
  end

  # Rails route-helper name ("new_pms_work_order") => "pms/work_orders#new",
  # derived from controller paths by resources-routing convention.
  def helper_index
    @helper_index ||= controllers.each_with_object({}) do |(controller_path, controller), index|
      *namespace, resource = controller_path.split("/")
      plural = [ *namespace, resource ].join("_")
      singular = [ *namespace, resource.singularize ].join("_")
      controller[:actions].each do |action|
        names = case action
        when "index" then [ plural, "#{plural}_index" ]
        when "show" then [ singular ]
        when "new" then [ "new_#{singular}" ]
        when "edit" then [ "edit_#{singular}" ]
        else [ "#{action}_#{plural}", "#{action}_#{singular}" ]
        end
        names.each { |name| index[name] ||= "#{controller_path}##{action}" }
      end
    end
  end
end
