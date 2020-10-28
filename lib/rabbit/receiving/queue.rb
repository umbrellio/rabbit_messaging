# frozen_string_literal: true

require "rabbit"
require "rabbit/receiving/message"
require "rabbit/receiving/handler_resolver"

class Rabbit::Receiving::Queue
  attr_reader :message, :arguments, :handler, :queue_name, :ignore_conversion

  delegate :queue, to: :handler

  def initialize(raw_message, arguments)
    @message           = Rabbit::Receiving::Message.build(raw_message, arguments)
    @handler           = Rabbit::Receiving::HandlerResolver.handler_for(message)
    @arguments         = arguments
    @queue_name        = resolved_queue_name
    @ignore_conversion = handler.ignore_queue_conversion
  end

  def name
    if queue_name
      calculated_queue_name
    else
      default_queue_name(ignore_conversion: ignore_conversion)
    end
  rescue
    default_queue_name
  end

  private

  def resolved_queue_name
    queue.is_a?(Proc) ? queue.call(message, arguments) : queue
  end

  def calculated_queue_name
    Rabbit.queue_name(queue_name, ignore_conversion: ignore_conversion)
  end

  def default_queue_name
    Rabbit.default_queue_name
  end
end
