# frozen_string_literal: true

require "rabbit"
require "rabbit/receiving"
require "rabbit/event_handler"

module Rabbit::Receiving::HandlerResolver
  UnsupportedEvent = Class.new(StandardError)

  class << self
    def handler_for(message)
      @handler_cache ||= Hash.new do |cache, (group_id, event)|
        handler = unmemoized_handler_for(group_id, event)
        cache[[group_id, event]] = handler if Rabbit.config.environment == :production
        handler
      end

      @handler_cache[[message.group_id, message.event]]
    end

    private

    def unmemoized_handler_for(group_id, event)
      name = "rabbit/handler/#{group_id}/#{event}".camelize
      handler = name.safe_constantize
      if handler && handler < Rabbit::EventHandler
        handler
      else
        raise UnsupportedEvent, "#{event.inspect} event from #{group_id.inspect} group is not " \
                                "supported, it requires a #{name.inspect} class inheriting from " \
                                "\"Rabbit::EventHandler\" to be defined"
      end
    end
  end
end
