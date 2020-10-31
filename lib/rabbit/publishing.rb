# frozen_string_literal: true

require "rabbit/publishing/message"

module Rabbit
  module Publishing
    autoload :Job, "rabbit/publishing/job"
    autoload :ChannelsPool, "rabbit/publishing/channels_pool"
    extend self

    MUTEX = Mutex.new

    def publish(msg)
      return if Rabbit.config.environment.in? %i[test development]

      pool.with_channel msg.confirm_select? do |ch|
        ch.basic_publish *msg.basic_publish_args

        raise MessageNotDelivered, "RabbitMQ message not delivered: #{msg}" \
          if msg.confirm_select? && !ch.wait_for_confirms

        log msg
      end
    rescue Timeout::Error
      raise MessageNotDelivered, <<~MESSAGE
        Timeout while sending message #{msg}. Possible reasons:
          - #{msg.real_exchange_name} exchange is not found
          - RabbitMQ is extremely high loaded
      MESSAGE
    end

    def pool
      MUTEX.synchronize { @pool = ChannelsPool.new(create_client) }
    end

    private

    def create_queue_if_not_exists(channel, message)
      channel.queue(message.routing_key, durable: true)
    end

    def create_client
      config = Rails.application.config_for("sneakers") rescue {}
      config = config["bunny_options"].to_h.symbolize_keys

      Bunny.new(config).start
    end

    def log(message)
      @logger ||= Rabbit.config.publish_logger

      headers = [
        message.real_exchange_name, message.routing_key, message.event,
        message.confirm_select? ? "confirm" : "no-confirm"
      ]

      @logger.debug "#{headers.join ' / '}: #{message.data}"
    end
  end
end
