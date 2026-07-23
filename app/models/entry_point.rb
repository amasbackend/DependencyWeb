# frozen_string_literal: true

class EntryPoint < ApplicationRecord
  belongs_to :company
  belongs_to :action_page, optional: true
  belongs_to :ui_menu, optional: true

  CHANNELS = %w[web api].freeze
  ENTRY_TYPES = %w[page api export pdf].freeze

  validates :channel, inclusion: { in: CHANNELS }
  validates :entry_type, inclusion: { in: ENTRY_TYPES }
end
