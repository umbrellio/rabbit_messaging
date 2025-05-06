# frozen_string_literal: true

require "tainbox"

require "rabbit"
require "rabbit/receiving/queue"
require "rabbit/receiving/job"

class Rabbit::Receiving::Receive
  include Tainbox

  attribute :message
  attribute :delivery_info
  attribute :arguments

  def call
    log!
    call_hooks(before_hooks)
    process_message
    call_hooks(after_hooks)
  end

  def log!
    message_parts = message.scan(/.{1,#{Rabbit.config.logger_message_size_limit}}/)

    message_parts.each do |message_part|
      Rabbit.config.receive_logger.debug(
        [message_part, delivery_info, arguments].join(" / "),
      )
    end
  end

  def process_message
    job_class
      .set(queue: queue_name, **job_configs)
      .perform_later(message, message_info)
  end

  def call_hooks(hooks)
    hooks.each do |hook_proc|
      hook_proc.call(message, message_info)
    end
  end

  def before_hooks
    Rabbit.config.before_receiving_hooks || []
  end

  def after_hooks
    Rabbit.config.after_receiving_hooks || []
  end

  def message_info
    arguments.merge(
      delivery_info.slice(:exchange, :routing_key),
    )
  end

  def queue
    @queue ||= Rabbit::Receiving::Queue.new(message, arguments)
  end

  def job_configs
    queue.handler.additional_job_configs
  end

  def queue_name
    queue.name
  end

  def job_class
    Rabbit.config.receiving_job_class_callable&.call(
      message: message,
      delivery_info: delivery_info,
      arguments: arguments,
    ) || Rabbit::Receiving::Job
  end
end
