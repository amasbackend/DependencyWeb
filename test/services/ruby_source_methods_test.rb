require "test_helper"

class RubySourceMethodsTest < ActiveSupport::TestCase
  test "splits methods with visibility and the route comment directly above each" do
    methods = RubySourceMethods.call(SCREEN_FIXTURE_FILES.fetch("app/controllers/orders_controller.rb")).index_by(&:name)

    assert_equal %w[index new create order_params], methods.keys
    assert_equal "/orders", methods["index"].route_comment
    assert_equal "/orders", methods["create"].route_comment
    assert_not methods["create"].private
    assert methods["order_params"].private
    assert_match "Orders::Create.result", methods["create"].body
    assert_no_match(/Orders::Create/, methods["new"].body)
  end
end
