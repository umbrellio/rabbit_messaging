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
    attribute :hooks, default: {}
    attribute :environment, Symbol, default: :production
    attribute :queue_name_conversion
    attribute :receiving_job_class_callable
    attribute :exception_notifier, default: -> { default_exception_notifier }

    def validate!
      raise InvalidConfig, "mising project_id" unless project_id
      raise InvalidConfig, "mising group_id" unless group_id

      unless environment.in? %i[test development production]
        raise "environment should be one of (test, development, production)"
      end
    end

    def app_name
      [group_id, project_id].join(".")
    end

    alias_method :read_queue, :app_name

    private

    def default_exception_notifier
      -> (e) { ExceptionNotifier.notify_exception(e) }
    end
  end

  extend self

  def config
    @config ||= Config.new
    yield(@config) if block_given?
    @config
  end

  alias_method :configure, :config

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
