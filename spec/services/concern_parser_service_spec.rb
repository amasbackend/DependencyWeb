# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConcernParserService do
  subject(:service) { described_class.new }

  it "extracts include statements" do
    content = <<~RUBY
      class ExamineRecord::Update < Actor
        include ExamineRecordParamBuilding
    RUBY

    expect(service.parse(content)).to eq(["ExamineRecordParamBuilding"])
  end

  it "returns empty array for blank content" do
    expect(service.parse("")).to eq([])
  end

  it "maps concern file path to module name" do
    name = service.concern_name_from_file_path("app/actors/concerns/examine_record_param_building.rb")
    expect(name).to eq("ExamineRecordParamBuilding")
  end
end
