# frozen_string_literal: true

require "active_support/core_ext/class/attribute"

class Rabbit::EventHandler
  attr_accessor :project_id, :data, :message_info

  class << self
    attr_accessor :queue, :ignore_queue_conversion, :additional_job_configs

    def inherited(subclass)
      super
      subclass.ignore_queue_conversion = false
      subclass.additional_job_configs = {}
    end

    private

    def queue_as(queue = nil, &block)
      self.queue = queue || block
    end

    def job_config(**config_opts)
      additional_job_configs.merge!(config_opts)
    end

    def job_configs(**config_opts)
      self.additional_job_configs = config_opts
    end
  end

  def initialize(message)
    assign_attributes(message.data)

    self.data = message.data
    self.project_id = message.project_id
    self.message_info = message.arguments
  end

  def assign_attributes(attrs = {})
    attrs.each do |key, value|
      setter = "#{key}="
      public_send(setter, value) if respond_to?(setter)
    end
  end
end
