require "test_helper"

class Projects::BuildBusinessFeaturesTest < ActiveSupport::TestCase
  def setup_indexed_project
    fixture_dir = build_fixture_rails_repo
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
    assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
    assert Projects::IndexCode.result(project: project).success?
    project
  end

  test "builds CRUD features via the rule table and links them to the matching controller-action code entity" do
    with_scratch_repository_root do
      project = setup_indexed_project
      modules_result = Projects::BuildBusinessModules.result(project: project)
      assert modules_result.success?

      result = Projects::BuildBusinessFeatures.result(project: project, parsed_routes: modules_result.parsed_routes)

      assert result.success?
      project.reload
      assert_equal "completed", project.analysis_status

      index_feature = project.business_features.find_by(slug: "index")
      assert_equal "使用者列表", index_feature.name
      assert_equal "route_derived", index_feature.source

      code_entity = project.code_entities.find_by(class_name: "UsersController", method_name: "index")
      assert index_feature.code_entities.include?(code_entity)

      assert_equal "crud_convention_derived", index_feature.operator_path.confidence_source
      assert_not index_feature.operator_path.needs_manual_review
    end
  end

  test "uses the route comment directly for a custom action, without needing the LLM" do
    with_scratch_repository_root do
      project = setup_indexed_project
      modules_result = Projects::BuildBusinessModules.result(project: project)

      result = Projects::BuildBusinessFeatures.result(project: project, parsed_routes: modules_result.parsed_routes)

      assert result.success?
      feature = project.business_features.find_by(slug: "activate")
      assert_equal "啟用使用者", feature.name
      assert_equal "locale_derived", feature.source
      assert_equal "route_comment_derived", feature.operator_path.confidence_source
      assert_not feature.operator_path.needs_manual_review
      assert_equal [ "使用者", "啟用使用者" ], feature.operator_path.segments.map(&:label)
    end
  end

  test "calls the LLM to name a custom action with no comment, and links the result" do
    with_scratch_repository_root do
      project = setup_indexed_project
      modules_result = Projects::BuildBusinessModules.result(project: project)

      fake_response = Llm::Response.new(content: '{"name":"封存使用者"}', provider: "gemini")
      fake_provider = Object.new
      fake_provider.define_singleton_method(:generate) { |**| fake_response }

      result = nil
      Llm::Provider.stub :current, fake_provider do
        result = Projects::BuildBusinessFeatures.result(project: project, parsed_routes: modules_result.parsed_routes)
      end

      assert result.success?
      feature = project.business_features.find_by(slug: "archive")
      assert_equal "封存使用者", feature.name
      assert_equal "llm_inferred", feature.source

      link = FeatureCodeEntity.find_by(business_feature: feature)
      assert_equal "llm_inferred", link.source

      assert_equal "controller_action_only", feature.operator_path.confidence_source
      assert feature.operator_path.needs_manual_review
    end
  end

  test "re-syncing keeps feature rows (and the analyses linked to them) and doesn't re-ask the LLM" do
    with_scratch_repository_root do
      project = setup_indexed_project
      calls = 0
      fake_provider = Object.new
      fake_provider.define_singleton_method(:generate) { |**| calls += 1; Llm::Response.new(content: '{"name":"封存使用者"}', provider: "gemini") }

      Llm::Provider.stub :current, fake_provider do
        2.times do |i|
          modules_result = Projects::BuildBusinessModules.result(project: project)
          assert Projects::BuildBusinessFeatures.result(project: project, parsed_routes: modules_result.parsed_routes).success?
          next unless i.zero?

          @archive_id = project.business_features.find_by(slug: "archive").id
          analysis = project.pull_request_analyses.create!(pr_number: 1)
          @item = analysis.impact_items.create!(business_feature_id: @archive_id, impact_level: "direct_change")
        end
      end

      assert_equal 1, calls, "the second sync reuses the LLM-given name"
      assert_equal @archive_id, project.business_features.find_by(slug: "archive").id
      assert_equal @archive_id, @item.reload.business_feature_id
      assert_equal "封存使用者", project.business_features.find(@archive_id).name
    end
  end

  test "skips (rather than crashes) a custom action when the LLM call itself fails" do
    with_scratch_repository_root do
      project = setup_indexed_project
      modules_result = Projects::BuildBusinessModules.result(project: project)

      failing_provider = Object.new
      def failing_provider.generate(**)
        raise Llm::Provider::Error, "no API key configured"
      end

      result = nil
      Llm::Provider.stub :current, failing_provider do
        result = Projects::BuildBusinessFeatures.result(project: project, parsed_routes: modules_result.parsed_routes)
      end

      assert result.success?
      assert_nil project.business_features.find_by(slug: "archive")
    end
  end
end
