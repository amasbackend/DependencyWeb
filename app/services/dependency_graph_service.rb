# frozen_string_literal: true

class DependencyGraphService
  attr_reader :action_pages, :action_pages_by_name, :callers_of, :model_consumers_of, :relate_models_by_name

  def initialize(company)
    @company = company
    @action_pages = ActionPage.where(company: company).includes(:management_page, :relate_models).to_a
    build_graph!
  end

  # @return [Hash{ActionPage => Integer}] depth 1 = caller, 2 = caller_l2
  def callers_of_actor(actor_name, max_depth: 2)
    result = {}
    frontier = callers_of[actor_name] || []
    depth = 1

    while frontier.any? && depth <= max_depth
      next_frontier = []
      frontier.each do |action_page|
        next if result.key?(action_page)

        result[action_page] = depth
        (callers_of[action_page.name] || []).each do |parent_page|
          next_frontier << parent_page unless result.key?(parent_page)
        end
      end
      frontier = next_frontier.uniq
      depth += 1
    end

    result
  end

  private

  def build_graph!
    @action_pages_by_name = @action_pages.index_by(&:name)
    @callers_of = Hash.new { |h, k| h[k] = [] }
    @model_consumers_of = Hash.new { |h, k| h[k] = [] }
    @relate_models_by_name = Hash.new { |h, k| h[k] = [] }

    @action_pages.each do |action_page|
      called_actors(action_page).each do |called_actor|
        @callers_of[called_actor] << action_page
      end

      relate_model_names(action_page).each do |model_name|
        @model_consumers_of[model_name] << action_page
      end

      action_page.relate_models.each do |relate_model|
        @relate_models_by_name[relate_model.name] << relate_model
      end
    end
  end

  def relate_action_names(action_page)
    Array(action_page.relate_action).map(&:to_s).reject(&:blank?)
  end

  def relate_model_names(action_page)
    Array(action_page.relate_model).map(&:to_s).reject(&:blank?)
  end

  def called_actors(action_page)
    (relate_action_names(action_page) + Array(action_page.play_chain).map(&:to_s)).uniq.reject(&:blank?)
  end
end
