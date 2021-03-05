# frozen_string_literal: true

require "tainbox"

module Rabbit::Publishing
  class Message
    include Tainbox

    attribute :routing_key,    String
    attribute :event,          String
    attribute :data,           default: {}
    attribute :exchange_name,  default: []
    attribute :confirm_select, default: true
    attribute :realtime,       default: false
    attribute :headers
    attribute :message_id

    alias_method :confirm_select?, :confirm_select
    alias_method :realtime?, :realtime

    def to_hash
      {
        **attributes,
        data: JSON.parse(data.to_json),
      }
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
      super(Array(names).map(&:to_s))
    end

    def real_exchange_name
      [Rabbit.config.group_id, Rabbit.config.project_id, *exchange_name].join(".")
    end

    def headers
      super || {}
    end
  end
end
