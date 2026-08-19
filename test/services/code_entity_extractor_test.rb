require "test_helper"

class CodeEntityExtractorTest < ActiveSupport::TestCase
  test "classifies real graphify output into Rails-typed code entities" do
    dir = build_fixture_rails_repo
    graphify_result = Graphify::Analyze.result(path: dir)
    assert graphify_result.success?

    entities = CodeEntityExtractor.call(
      graph_json_path: File.join(graphify_result.output_dir, "graph.json"),
      worktree_path: dir,
    )

    by_name = entities.index_by { |e| e[:name] }

    model = by_name["User"]
    assert_equal "model", model[:entity_type]
    assert_equal "app/models/user.rb", model[:file_path]
    assert_equal 1, model[:line_start]

    concern = by_name["Trackable"]
    assert_equal "concern", concern[:entity_type]

    controller = by_name["UsersController"]
    assert_equal "controller", controller[:entity_type]

    controller_action = by_name["UsersController#show"]
    assert_equal "controller", controller_action[:entity_type]
    assert_equal "UsersController", controller_action[:class_name]
    assert_equal "show", controller_action[:method_name]

    actor = by_name["Users::Update"]
    assert_equal "actor", actor[:entity_type]

    view = entities.find { |e| e[:entity_type] == "view" }
    assert_equal "app/views/users/index.html.erb", view[:file_path]

    routes = entities.select { |e| e[:entity_type] == "route" }
    assert routes.any? { |r| r[:name].include?("resources :users") }
    assert routes.any? { |r| r[:name].include?('root "users#index"') }

    entities.each { |e| assert e[:signature_hash].present? }
  end
end
