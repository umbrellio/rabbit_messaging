# frozen_string_literal: true

require "sneakers"

require "rabbit"
require "rabbit/receiving/message"
require "rabbit/receiving/malformed_message"
require "rabbit/receiving/handler_resolver"

module Rabbit::Receiving
  autoload :Job, "rabbit/receiving/job"

  class Worker
    include Sneakers::Worker

    def self.logger
      @logger ||= Rabbit.config.receive_logger
    end

    def work_with_params(message, delivery_info, arguments)
      message = message.dup.force_encoding("UTF-8")
      self.class.logger.debug([message, delivery_info, arguments].join(" / "))
      job_class.set(queue: queue(message, arguments)).perform_later(message, arguments.to_h)
      ack!
    rescue => error
      raise if Rabbit.config.environment == :test
      Rabbit.config.exception_notifier.call(error)
      requeue!
    end

    private

    def queue(message, arguments)
      message           = Rabbit::Receiving::Message.build(message, arguments)
      handler           = Rabbit::Receiving::HandlerResolver.handler_for(message)
      queue_name        = handler.queue
      ignore_conversion = handler.ignore_queue_conversion

      return Rabbit.default_queue_name(ignore_conversion: ignore_conversion) unless queue_name

      calculated_queue = begin
        queue_name.is_a?(Proc) ? queue_name.call(message, arguments) : queue_name
      end

      Rabbit.queue_name(calculated_queue, ignore_conversion: ignore_conversion)
    rescue
      Rabbit.default_queue_name
    end

    def job_class
      Rabbit.config.receiving_job_class_callable&.call || Job
    end
  end
end
