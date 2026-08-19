class TestCase < ApplicationRecord
  enumerize :case_type, in: ModelEnum.test_case_type_enum

  belongs_to :test_report
  belongs_to :business_feature, optional: true
  belongs_to :impact_item, optional: true

  validates :name, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
end
