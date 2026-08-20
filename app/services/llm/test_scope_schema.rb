module Llm
  # Validates the LLM's structured JSON response against §37's schema before
  # any of it is trusted enough to persist. A malformed or incomplete
  # response is treated exactly like a network/API failure (§63 — llm_failed,
  # retryable without redoing git/Graphify/impact work) — never silently
  # patched, defaulted, or guessed at (§36).
  class TestScopeSchema
    class ValidationError < StandardError; end

    REQUIRED_STRING = ->(v) { v.is_a?(String) && v.present? }
    CASE_TYPES = %w[core_change direct_impact indirect_impact].freeze

    def self.validate(data)
      new(data).validate
    end

    def initialize(data)
      @data = data
      @errors = []
    end

    def validate
      return [ "response is not a JSON object" ] unless @data.is_a?(Hash)

      check_summary
      check_string_array("affected_modules")
      check_test_cases("test_cases", require_case_type: true)
      check_test_cases("regression_cases", require_case_type: false)
      check_string_array("pass_criteria")
      check_string_array("manual_checks")
      check_uncertain_items
      check_optional_string_array("preparation")

      @errors
    end

    private

    def check_summary
      summary = @data["summary"]
      unless summary.is_a?(Hash)
        @errors << "summary is missing"
        return
      end

      @errors << "summary.title is missing" unless REQUIRED_STRING.call(summary["title"])
    end

    def check_string_array(key)
      @errors << "#{key} must be an array" unless @data[key].is_a?(Array)
    end

    # Phase 13's "測試前準備" section (§39) — supplementary, so a missing key
    # is fine (Reports::Build treats it as empty); present-but-wrong-type is
    # still a real error, same as any other array field.
    def check_optional_string_array(key)
      @errors << "#{key} must be an array" if @data.key?(key) && !@data[key].is_a?(Array)
    end

    def check_test_cases(key, require_case_type:)
      cases = @data[key]
      unless cases.is_a?(Array)
        @errors << "#{key} must be an array"
        return
      end

      cases.each_with_index { |c, i| check_test_case("#{key}[#{i}]", c, require_case_type: require_case_type) }
    end

    def check_test_case(prefix, c, require_case_type:)
      unless c.is_a?(Hash)
        @errors << "#{prefix} must be an object"
        return
      end

      @errors << "#{prefix}.name is missing" unless REQUIRED_STRING.call(c["name"])
      @errors << "#{prefix}.verification_purpose is missing" unless REQUIRED_STRING.call(c["verification_purpose"])
      @errors << "#{prefix}.expected_result is missing" unless REQUIRED_STRING.call(c["expected_result"])
      @errors << "#{prefix}.steps must be a non-empty array" unless c["steps"].is_a?(Array) && c["steps"].any?
      @errors << "#{prefix}.evidence must be a non-empty array" unless c["evidence"].is_a?(Array) && c["evidence"].any?
      @errors << "#{prefix}.impact_item_refs must be a non-empty array" unless c["impact_item_refs"].is_a?(Array) && c["impact_item_refs"].any?
      @errors << "#{prefix}.case_type must be one of #{CASE_TYPES}" if require_case_type && !CASE_TYPES.include?(c["case_type"])
    end

    def check_uncertain_items
      items = @data["uncertain_items"]
      unless items.is_a?(Array)
        @errors << "uncertain_items must be an array"
        return
      end

      items.each_with_index do |item, i|
        @errors << "uncertain_items[#{i}].description is missing" unless item.is_a?(Hash) && REQUIRED_STRING.call(item["description"])
      end
    end
  end
end
