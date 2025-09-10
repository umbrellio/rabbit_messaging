# frozen_string_literal: true

module Rabbit::Publishing
  class Message
    attr_accessor :routing_key, :event, :data,
                  :confirm_select, :realtime, :headers, :message_id
    attr_reader :exchange_name

    alias_method :confirm_select?, :confirm_select
    alias_method :realtime?, :realtime

    def initialize(
      routing_key: nil,
      event: nil,
      data: {},
      exchange_name: [],
      confirm_select: true,
      realtime: false,
      headers: {},
      message_id: nil
    )
      self.routing_key = routing_key
      self.event = event&.to_s
      self.data = data
      self.exchange_name = Array(exchange_name)
      self.confirm_select = confirm_select
      self.realtime = realtime
      self.headers = headers
      self.message_id = message_id
    end

    def to_hash
      instance_variables.each_with_object({}) do |var, hash|
        key = var.to_s.delete("@").to_sym
        value = instance_variable_get(var)
        hash[key] = value
      end.merge(data: JSON.parse(data.to_json))
    end

    def to_s
      "#{real_exchange_name} -> #{routing_key} -> #{event}"
    end

    def basic_publish_args
      Rabbit.config.validate!

      raise "Routing key not specified" unless routing_key
      raise "Event name not specified" unless event

      options = {
        mandatory: confirm_select?,
        persistent: true,
        type: event,
        content_type: "application/json",
        app_id: Rabbit.config.app_name,
        headers: headers,
        message_id: message_id,
      }

      [JSON.dump(data), real_exchange_name, routing_key.to_s, options]
    end

    def exchange_name=(names)
      @exchange_name = Array(names).map(&:to_s)
    end

    def real_exchange_name
      [Rabbit.config.group_id, Rabbit.config.project_id, *exchange_name].join(".")
    end
  end
end
