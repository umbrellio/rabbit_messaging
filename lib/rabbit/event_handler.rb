# frozen_string_literal: true

require "tainbox"
require "active_support/core_ext/class/attribute"

class Rabbit::EventHandler
  include Tainbox

  attribute :project_id
  attribute :data
  attribute :message_info

  class_attribute :queue
  class_attribute :ignore_queue_conversion, default: false

  class << self
    private

    def queue_as(queue = nil, &block)
      self.queue = queue || block
    end
  end

  def initialize(message)
    self.attributes   = message.data
    self.data         = message.data
    self.project_id   = message.project_id
    self.message_info = message.arguments
  end
end
