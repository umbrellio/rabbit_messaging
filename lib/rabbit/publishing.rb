# frozen_string_literal: true

require "rabbit/publishing/message"

module Rabbit
  module Publishing
    autoload :Job, "rabbit/publishing/job"
    extend self

    MUTEX = Mutex.new

    class ChannelsPool
      class BaseQueue < Queue
        def initialize(session, max_size)
          @session    = session
          @max_size   = max_size
          @ch_size    = 0
          @create_mon = Mutex.new
        end

        def pop
          create_channel if size == 0

          super
        end

        def push(ch)
          return @ch_size -= 1 unless ch&.open?

          super
        end

        def init_channel
          @create_mon.synchronize do
            return unless @ch_size < @max_size

            push create_channel
            @ch_size += 1

            channel
          end
        end

        private

        def create_channel
          @session.create_channel
        end
      end

      class ConfirmQueue < BaseQueue
        def create_channel
          @session.create_channel.confirm_select
        end
      end

      def initialize(session)
        max_size = session.channel_max

        @pools = {
          true:  ConfirmQueue.new(session, max_size/2),
          false: BaseQueue.new(session, max_size/2)
        }.freeze
      end

      def with_channel(confirm)
        pool = @pools[confirm]
        ch = pool.pop
        yield ch
      ensure
        pool.push ch
      end
    end

    def publish(msg)
      # return unless client

      # channel = channel(message.confirm_select?)
      # channel.basic_publish(*message.basic_publish_args)
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
