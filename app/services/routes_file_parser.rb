require "active_support/core_ext/string/inflections"

# Parses config/routes.rb into resolved {controller:, action:, comment:}
# route entries, correctly qualifying controller names for routes nested
# inside `namespace`/`scope module:` blocks — Phase 5's CodeEntityExtractor
# deliberately does a flat line-scan (good enough for a raw catalog), but
# Phase 6 needs the real controller each route resolves to, which a flat scan
# gets wrong for anything namespaced (confirmed against the real target
# repo's routes.rb: most controllers live inside `namespace :setting do...end`
# etc). Still a deliberately shallow parse, not a full Rails routing-DSL
# interpreter — see docs/architecture_plan.md §3 for what's out of scope.
#
# The comment on a bare `resources :x # 客戶管理` line names the whole
# resource/module (confirmed against real data), not a single action — kept
# separately as `resource_comments` for Projects::BuildBusinessModules to
# consume, distinct from the per-action `routes` this class also returns.
class RoutesFileParser
  Route = Struct.new(:controller, :action, :comment, :standard, keyword_init: true)

  NAMESPACE_OPEN = /\A\s*(?:namespace|scope)\s+(?:module:\s*)?:?"?(?<name>[\w\/]+)"?.*\bdo\b\s*(\|.*\|)?\s*\z/
  RESOURCES_LINE = /\A\s*resources?\s+:(?<name>\w+)\s*(?<opts>.*)\z/
  MEMBER_ACTION_LINE = /\A\s*(?:get|post|patch|put|delete)\s+:(?<name>\w+),\s*on:\s*:(?:member|collection)/
  VERB_ROUTE = %r{\A\s*(?:get|post|patch|put|delete|match)\s+["'](?<path>[^"']+)["']\s*(?:=>|,\s*to:)\s*["'](?<target>[\w/]+#\w+)["']}
  ROOT_ROUTE = %r{\A\s*root\s+(?:to:\s*)?["'](?<target>[\w/]+#\w+)["']}
  GENERIC_DO = /\bdo\b\s*(\|.*\|)?\s*\z/
  END_LINE = /\A\s*end\s*\z/
  STANDARD_ACTIONS = %w[index show new create edit update destroy].freeze

  def self.call(routes_path:)
    new(routes_path).call
  end

  def initialize(routes_path)
    # chomp up front: RESOURCES_LINE's trailing `\z` can't match past a `\n`
    # (`.` doesn't consume newlines), which only broke lines with no comment
    # to strip — every commented line's code portion happened to already
    # exclude the newline, masking this for every line that had one.
    @lines = File.readlines(routes_path).map(&:chomp)
  end

  def call
    @namespace_stack = []
    @routes = []
    @resource_comments = {}
    @current_resource_controller = nil

    @lines.each { |raw_line| process_line(raw_line) }

    { routes: @routes, resource_comments: @resource_comments }
  end

  private

  # A `#` that appears inside a quoted string (e.g. the `#` in the route
  # target "work_orders#create") is not a comment marker — only a `#` outside
  # any quotes starts a real trailing comment. Scanning char-by-char with
  # simple quote tracking (routes.rb never nests quote types) distinguishes
  # the two; a naive `line.split("#", 2)` would truncate the target string
  # itself, and a naive `#.*\z` regex would (and did) match the wrong `#`.
  def split_code_and_comment(line)
    in_string = false
    quote_char = nil
    line.each_char.with_index do |char, index|
      if in_string
        in_string = false if char == quote_char
      elsif char == '"' || char == "'"
        in_string = true
        quote_char = char
      elsif char == "#"
        return [ line[0...index], line[(index + 1)..].to_s.strip.presence ]
      end
    end
    [ line, nil ]
  end

  def process_line(raw_line)
    code, comment = split_code_and_comment(raw_line)
    stripped = code.strip
    return if stripped.empty?

    if (m = NAMESPACE_OPEN.match(code))
      @namespace_stack.push(m[:name])
      return
    end

    if (m = RESOURCES_LINE.match(code))
      handle_resources(m, code, comment)
      return
    end

    if @current_resource_controller && (m = MEMBER_ACTION_LINE.match(code))
      @routes << Route.new(controller: @current_resource_controller, action: m[:name], comment: comment, standard: false)
      return
    end

    if (m = VERB_ROUTE.match(code))
      add_target_route(m[:target], comment)
      return
    end

    if (m = ROOT_ROUTE.match(code))
      add_target_route(m[:target], comment)
      return
    end

    if GENERIC_DO.match?(code)
      @namespace_stack.push(nil) # opaque block (member/collection do, etc.) — balance `end`, no namespace change
      return
    end

    return unless END_LINE.match?(code)

    @namespace_stack.pop
    @current_resource_controller = nil
  end

  def handle_resources(match, code, comment)
    resource = match[:name]
    controller = qualified_controller(resource)
    @resource_comments[controller] = comment if comment.present?

    only = extract_symbols(match[:opts], "only")
    except = extract_symbols(match[:opts], "except")
    actions = only || (STANDARD_ACTIONS - (except || []))
    actions.each { |action| @routes << Route.new(controller: controller, action: action, comment: nil, standard: true) }

    if GENERIC_DO.match?(code)
      @namespace_stack.push(nil)
      @current_resource_controller = controller
    end
  end

  def add_target_route(target, comment)
    controller_part, action = target.split("#")
    controller = qualified_controller_path(controller_part.split("/"))
    @routes << Route.new(controller: controller, action: action, comment: comment, standard: false)
  end

  def qualified_controller(resource)
    qualified_controller_path([ resource ])
  end

  def qualified_controller_path(segments)
    parts = [ *@namespace_stack.compact, *segments ].map { |s| s.to_s.camelize }
    parts[0...-1].push("#{parts.last}Controller").join("::")
  end

  def extract_symbols(opts, key)
    m = /#{key}:\s*\[([^\]]*)\]/.match(opts.to_s)
    return nil unless m

    m[1].scan(/:(\w+)/).flatten
  end
end
