require "application_system_test_case"

class GraphifyIdeTest < ApplicationSystemTestCase
  def sample_graph
    {
      "nodes" => [
        { "id" => "a", "label" => "Orders::Ship", "source_file" => "app/actors/orders/ship.rb", "_callable_class" => true, "community" => 1, "community_name" => "Ship" },
        { "id" => "a_call", "label" => ".call()", "source_file" => "app/actors/orders/ship.rb", "community" => 1, "community_name" => "Ship" },
        { "id" => "b_call", "label" => ".ship()", "source_file" => "app/controllers/orders_controller.rb", "community" => 2, "community_name" => "Controllers" },
      ],
      "links" => [
        { "source" => "a", "target" => "a_call", "relation" => "method" },
        { "source" => "b_call", "target" => "a_call", "relation" => "calls" },
      ],
    }
  end

  setup do
    @project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    @project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-1",
    )
    @analysis = @project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")
    @analysis.graphify_artifacts.create!(
      format: "graph_json", raw_content: "{}", graphify_version: "0.0.0-test", parsed_content: sample_graph,
    )
    changed_file = @analysis.changed_files.create!(file_path: "app/actors/orders/ship.rb", change_type: "modified")
    @analysis.changed_code_entities.create!(
      changed_file: changed_file, entity_type: "actor", class_name: "Orders::Ship", method_name: "call", change_kind: "modified",
    )
  end

  test "Graphify's own graph.html renders in the frame with its communities legend" do
    visit project_pull_request_analysis_path(@project, @analysis, tab: "impact", anchor: "graphify")

    within_frame find("iframe[title='Graphify 依賴圖']") do
      assert_selector "#graph canvas", wait: 10 # vis-network draws onto a <canvas> it creates itself
      within("#legend") do
        assert_text "Ship"
        assert_text "Controllers"
      end
    end
  end

  test "opening a node inside Graphify's panel populates the app-side inspector" do
    visit project_pull_request_analysis_path(@project, @analysis, tab: "impact", anchor: "graphify")

    within_frame find("iframe[title='Graphify 依賴圖']") do
      assert_selector "#graph canvas", wait: 10
      fill_in "search", with: "call"
      find(".search-item", text: ".call()").click
    end

    within "#graph-inspector" do
      assert_text "Actor"
      assert_text "app/actors/orders/ship.rb"
    end
  end
end
