# frozen_string_literal: true

require "tainbox"

require "rabbit"
require "rabbit/receiving/queue"

class Rabbit::Receiving::Receive
  autoload :Job, "rabbit/receiving/job"

  include Tainbox

  attribute :message
  attribute :delivery_info
  attribute :arguments

  def call
    log!
    call_hooks(:before)
    process_message
    call_hooks(:after)
  end

  def log!
    Rabbit.config.receive_logger.debug(
      [message, delivery_info, arguments].join(" / "),
    )
  end

  def process_message
    job_class
      .set(queue: queue)
      .perform_later(message, message_info)
  end

  def call_hooks(type)
    hooks(type).each do |hook_proc|
      hook_proc.call(message, message_info)
    end
  end

  def hooks(type)
    Rabbit.config.receiving_hooks.fetch(type, [])
  end

  def message_info
    arguments.merge(
      delivery_info.slice(:exchange, :routing_key),
    )
  end

  def queue
    Rabbit::Receiving::Queue.new(message, arguments).name
  end

  def job_class
    Rabbit.config.receiving_job_class_callable&.call || Rabbit::Receiving::Job
  end
end
