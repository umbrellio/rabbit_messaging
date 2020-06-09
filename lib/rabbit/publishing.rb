# frozen_string_literal: true

require "rabbit/publishing/message"

module Rabbit
  module Publishing
    autoload :Job, "rabbit/publishing/job"

    MUTEX = Mutex.new

    extend self

    attr_writer :logger

    def logger
      @logger ||= Logger.new(Rails.root.join("log", "rabbit.log"))
    end

    def publish(message)
      return unless client

      channel = channel(message.confirm_select?)
      channel.basic_publish(*message.basic_publish_args)

      if message.confirm_select? && !channel.wait_for_confirms
        raise MessageNotDelivered, "RabbitMQ message not delivered: #{message}"
      else
        log(message)
      end
    rescue Timeout::Error
      raise MessageNotDelivered, <<~MESSAGE
        Timeout while sending message #{message}. Possible reasons:
          - #{message.real_exchange_name} exchange is not found
          - RabbitMQ is extremely high loaded
      MESSAGE
    end

    def client
      MUTEX.synchronize { @client ||= create_client }
    end

    def channel(confirm)
      Thread.current[:bunny_channels] ||= {}
      channel = Thread.current[:bunny_channels][confirm]
      Thread.current[:bunny_channels][confirm] = create_channel(confirm) unless channel&.open?
      Thread.current[:bunny_channels][confirm]
    end

    private

    def create_queue_if_not_exists(channel, message)
      channel.queue(message.routing_key, durable: true)
    end

    def create_client
      return if Rabbit.config.environment == :test

      config = Rails.application.config_for("sneakers") rescue {}
      config = config["bunny_options"].to_h.symbolize_keys

      begin
        Bunny.new(config).start
      rescue
        raise unless Rabbit.config.environment == :development
      end
    end

    def create_channel(confirm)
      channel = client.create_channel
      channel.confirm_select if confirm
      channel
    end

    def log(message)
      headers = [
        message.real_exchange_name, message.routing_key, message.event,
        message.confirm_select? ? "confirm" : "no-confirm"
      ]

      logger.debug "#{headers.join ' / '}: #{message.data}"
    end
  end
end
