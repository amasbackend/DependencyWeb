# Decides a BusinessFeature's name/slug/source for one route, per the
# priority order from project_plan.md §13-15: an existing route-line comment
# always wins (it's the developers' own label, already proven against real
# data to cover even custom actions — see RoutesFileParser); failing that, the
# standard CRUD rule table from §14 handles index/show/new+create/edit+update
# /destroy; anything else (a custom, uncommented action — e.g. `cooling`,
# `scrap`) needs `needs_llm: true` — the caller (Projects::BuildBusinessFeatures)
# is responsible for the actual LLM call, this class only decides whether one
# is needed, so it stays a pure, cheap, fully-testable function.
class BusinessFeatureNamer
  # new/create share one feature ("新增X"), as do edit/update ("編輯X") — the
  # form-display action and the submit action are one feature from an
  # operator's point of view, not two (project_plan.md's own "使用者" example
  # lists exactly one "新增使用者" feature, not separate ones per HTTP verb).
  CRUD_GROUPS = {
    "index" => { slug: "index", template: "%s列表" },
    "show" => { slug: "show", template: "%s詳細資料" },
    "new" => { slug: "new", template: "新增%s" },
    "create" => { slug: "new", template: "新增%s" },
    "edit" => { slug: "edit", template: "編輯%s" },
    "update" => { slug: "edit", template: "編輯%s" },
    "destroy" => { slug: "destroy", template: "刪除%s" },
  }.freeze

  Result = Struct.new(:slug, :name, :source, :needs_llm, keyword_init: true)

  def self.call(route:, resource_label:)
    new(route, resource_label).call
  end

  def initialize(route, resource_label)
    @route = route
    @resource_label = resource_label
  end

  def call
    if route.comment.present?
      Result.new(slug: route.action, name: route.comment, source: "locale_derived", needs_llm: false)
    elsif (group = CRUD_GROUPS[route.action])
      Result.new(slug: group[:slug], name: format(group[:template], resource_label), source: "route_derived", needs_llm: false)
    else
      Result.new(slug: route.action, name: nil, source: "llm_inferred", needs_llm: true)
    end
  end

  private

  attr_reader :route, :resource_label
end
