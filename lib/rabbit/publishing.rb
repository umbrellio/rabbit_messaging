# frozen_string_literal: true

require "rabbit/publishing/message"

module Rabbit
  module Publishing
    autoload :Job, "rabbit/publishing/job"
    autoload :ChannelsPool, "rabbit/publishing/channels_pool"
    extend self

    MUTEX = Mutex.new

    def publish(msg) # rubocop:disable Metrics/MethodLength
      return if Rabbit.config.skip_publish?

      attempt = 0
      begin
        pool.with_channel msg.confirm_select? do |ch|
          ch.basic_publish *msg.basic_publish_args

          raise MessageNotDelivered, "RabbitMQ message not delivered: #{msg}" \
            if msg.confirm_select? && !ch.wait_for_confirms

          log msg
        end
      rescue *Rabbit.config.connection_reset_exceptions => error
        attempt += 1
        if attempt <= Rabbit.config.connection_reset_max_retries
          sleep(Rabbit.config.connection_reset_timeout)
          reinitialize_channels_pool
          retry
        else
          raise error
        end
      rescue Timeout::Error
        raise MessageNotDelivered, <<~MESSAGE
          Timeout while sending message #{msg}. Possible reasons:
            - #{msg.real_exchange_name} exchange is not found
            - RabbitMQ is extremely high loaded
        MESSAGE
      end
    end

    def pool
      MUTEX.synchronize { @pool ||= ChannelsPool.new(create_client) }
    end

    private

    def create_queue_if_not_exists(channel, message)
      channel.queue(message.routing_key, durable: true)
    end

    def create_client
      config = Rabbit.sneakers_config
      config = config[:bunny_options].to_h.symbolize_keys

      Bunny.new(config).start
    end

    def log(message)
      @logger ||= Rabbit.config.publish_logger

      metadata = [
        message.real_exchange_name, message.routing_key, JSON.dump(message.headers),
        message.event, message.confirm_select? ? "confirm" : "no-confirm"
      ]

      @logger.debug "#{metadata.join ' / '}: #{JSON.dump(message.data)}"
    end

    def reinitialize_channels_pool
      @pool = nil
    end
  end
end
