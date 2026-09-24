# frozen_string_literal: true

require "rabbit/publishing/message"

module Rabbit
  module Publishing
    autoload :Job, "rabbit/publishing/job"
    autoload :ChannelsPool, "rabbit/publishing/channels_pool"
    extend self

    MUTEX = Mutex.new

    def publish(msg)
      return if Rabbit.config.skip_publish?

      attempt = 0
      retried_on_live_connection = false
      begin
        current_pool = pool
        deliver(current_pool, msg)
      rescue Bunny::ChannelAlreadyClosed => error
        if ChannelsPool.live?(error.channel&.connection)
          raise error if retried_on_live_connection

          retried_on_live_connection = true
          retry
        end

        attempt = reconnect_or_raise(error, attempt, current_pool)
        retry
      rescue *Rabbit.config.connection_reset_exceptions => error
        attempt = reconnect_or_raise(error, attempt, current_pool)
        retry
      rescue Timeout::Error
        raise MessageNotDelivered, timeout_message(msg)
      end
    end

    def pool
      MUTEX.synchronize { @pool ||= ChannelsPool.new(create_client) }
    end

    private

    def deliver(channels_pool, msg)
      channels_pool.with_channel msg.confirm_select? do |ch|
        ch.basic_publish *msg.basic_publish_args

        raise MessageNotDelivered, "RabbitMQ message not delivered: #{msg}" \
          if msg.confirm_select? && !ch.wait_for_confirms

        log msg
      end
    end

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

      return log_compressed(message.dumped_data, metadata: metadata) if message.compress

      log_by_parts(message, metadata: metadata)
    end

    def timeout_message(msg)
      <<~MESSAGE
        Timeout while sending message #{msg}. Possible reasons:
          - #{msg.real_exchange_name} exchange is not found
          - RabbitMQ is extremely high loaded
      MESSAGE
    end

    def reconnect_or_raise(error, attempt, failed_pool)
      attempt += 1
      raise error if attempt > Rabbit.config.connection_reset_max_retries

      sleep(Rabbit.config.connection_reset_timeout)
      reinitialize_channels_pool(failed_pool)
      attempt
    end

    def reinitialize_channels_pool(failed_pool)
      MUTEX.synchronize do
        return unless @pool.equal?(failed_pool)

        @pool = ChannelsPool.new(create_client)
      end

      failed_pool&.close
    end

    def log_compressed(message_for_publish, metadata:)
      formatted_message = Rabbit::Helper.generate_message(
        message_for_publish, 1, 0, compressed: true
      )

      @logger.debug "#{metadata.join ' / '}: #{formatted_message}"
    end

    def log_by_parts(message_for_publish, metadata:)
      message_parts =
        message_for_publish
          .dumped_data
          .scan(/.{1,#{Rabbit.config.logger_message_size_limit}}/)

      message_parts.each_with_index do |message_part, index|
        formatted_message = Rabbit::Helper.generate_message(
          message_part, message_parts.size, index
        )
        @logger.debug "#{metadata.join ' / '}: #{formatted_message}"
      end
    end
  end
end
