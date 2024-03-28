# frozen_string_literal: true

require "tainbox"

require "rabbit/version"
require "rabbit/daemon"
require "rabbit/publishing"
require "rabbit/event_handler"

require "rabbit/extensions/bunny/channel"

module Rabbit
  InvalidConfig = Class.new(StandardError)
  MessageNotDelivered = Class.new(StandardError)

  class Config
    include Tainbox

    attribute :group_id, Symbol
    attribute :project_id, Symbol
    attribute :queue_suffix, String
    attribute :hooks, default: {}
    attribute :environment, Symbol, default: :production
    attribute :queue_name_conversion
    attribute :receiving_job_class_callable
    attribute :exception_notifier
    attribute :before_receiving_hooks, default: []
    attribute :after_receiving_hooks, default: []
    attribute :skip_publishing_in, default: %i[test development]
    attribute :backoff_handler_max_retries, Integer, default: 6

    attribute :receive_logger, default: lambda {
      Logger.new(Rails.root.join("log", "incoming_rabbit_messages.log"))
    }

    attribute :publish_logger, default: lambda {
      Logger.new(Rails.root.join("log", "rabbit.log"))
    }

    attribute :malformed_logger, default: lambda {
      Logger.new(Rails.root.join("log", "malformed_messages.log"))
    }

    def validate!
      raise InvalidConfig, "missing project_id" unless project_id
      raise InvalidConfig, "missing group_id" unless group_id
      raise InvalidConfig, "missing exception_notifier" unless exception_notifier

      unless environment.in? %i[test development production]
        raise "environment should be one of (test, development, production)"
      end
    end

    def skip_publish?
      skip_publishing_in.include?(environment)
    end

    def app_name
      [group_id, project_id].join(".")
    end

    def read_queue
      [app_name, queue_suffix].compact.join(".")
    end
  end

  extend self

  def config
    @config ||= Config.new
    yield(@config) if block_given?
    @config
  end

  def configure
    yield(config)
    config.validate!
  end

  def publish(message_options)
    message = Publishing::Message.new(message_options)

    if message.realtime?
      Publishing.publish(message)
    else
      Publishing::Job.set(queue: default_queue_name).perform_later(message.to_hash)
    end
  end

  def queue_name(queue, ignore_conversion: false)
    return queue if ignore_conversion
    config.queue_name_conversion ? config.queue_name_conversion.call(queue) : queue
  end

  def default_queue_name(ignore_conversion: false)
    queue_name(:default, ignore_conversion: ignore_conversion)
  end
end
