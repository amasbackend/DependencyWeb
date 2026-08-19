require "test_helper"
require "ostruct"

class ProjectImportJobTest < ActiveJob::TestCase
  def stub_chain(overrides = {}, &block)
    calls = []
    modules_stub = overrides[:build_business_modules] || ->(project:) { calls << :build_business_modules; OpenStruct.new(parsed_routes: []) }

    Projects::Import.stub :call, (overrides[:import] || ->(project:) { calls << :import }) do
      Repositories::Clone.stub :call, (overrides[:clone] || ->(project:) { calls << :clone }) do
        Projects::IndexCode.stub :call, (overrides[:index_code] || ->(project:) { calls << :index_code }) do
          Projects::BuildBusinessModules.stub :call, modules_stub do
            Projects::BuildBusinessFeatures.stub :call, (overrides[:build_business_features] || ->(project:, parsed_routes:) { calls << :build_business_features }) do
              block.call
            end
          end
        end
      end
    end

    calls
  end

  test "runs every pipeline step in sequence" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")

    calls = stub_chain { ProjectImportJob.new.perform(project_id: project.id) }

    assert_equal [ :import, :clone, :index_code, :build_business_modules, :build_business_features ], calls
  end

  test "does not run any later step when import fails" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    failing_import = lambda do |project:|
      project.update!(status: "failed", error_message: "boom")
      raise ServiceActor::Failure, ServiceActor::Result.new(error: "boom")
    end

    calls = stub_chain(import: failing_import) do
      assert_raises(ServiceActor::Failure) { ProjectImportJob.new.perform(project_id: project.id) }
    end

    assert_empty calls
  end

  test "does not run index_code or later when clone fails" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    failing_clone = lambda do |project:|
      project.update!(status: "failed", error_message: "boom")
      raise ServiceActor::Failure, ServiceActor::Result.new(error: "boom")
    end

    calls = stub_chain(clone: failing_clone) do
      assert_raises(ServiceActor::Failure) { ProjectImportJob.new.perform(project_id: project.id) }
    end

    assert_equal [ :import ], calls
  end

  test "passes BuildBusinessModules' parsed_routes through to BuildBusinessFeatures" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    received_routes = nil
    fake_routes = [ :a_route ]

    stub_chain(
      build_business_modules: ->(project:) { OpenStruct.new(parsed_routes: fake_routes) },
      build_business_features: ->(project:, parsed_routes:) { received_routes = parsed_routes },
    ) { ProjectImportJob.new.perform(project_id: project.id) }

    assert_equal fake_routes, received_routes
  end
end
