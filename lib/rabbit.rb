# frozen_string_literal: true

require "rabbit/version"
require "rabbit/daemon"
require "rabbit/publishing"
require "rabbit/event_handler"

require "rabbit/extensions/bunny/channel"

module Rabbit
  InvalidConfig = Class.new(StandardError)
  MessageNotDelivered = Class.new(StandardError)

  class Config
    attr_accessor :group_id,
                  :project_id,
                  :queue_suffix,
                  :hooks,
                  :queue_name_conversion,
                  :receiving_job_class_callable,
                  :publishing_job_class_callable,
                  :default_publishing_job_queue,
                  :handler_resolver_callable,
                  :exception_notifier,
                  :before_receiving_hooks,
                  :after_receiving_hooks,
                  :skip_publishing_in,
                  :use_backoff_handler,
                  :backoff_handler_max_retries,
                  :connection_reset_max_retries,
                  :connection_reset_timeout,
                  :connection_reset_exceptions,
                  :logger_message_size_limit

    attr_reader :environment
    attr_writer :receive_logger, :publish_logger, :malformed_logger

    def initialize( # rubocop:disable Metrics/MethodLength
      group_id: nil,
      project_id: nil,
      queue_suffix: nil,
      hooks: {},
      environment: :production,
      queue_name_conversion: nil,
      receiving_job_class_callable: nil,
      publishing_job_class_callable: nil,
      default_publishing_job_queue: :default,
      handler_resolver_callable: nil,
      exception_notifier: nil,
      before_receiving_hooks: [],
      after_receiving_hooks: [],
      skip_publishing_in: %i[test development],
      use_backoff_handler: false,
      backoff_handler_max_retries: 6,
      connection_reset_max_retries: 10,
      connection_reset_timeout: 0.2,
      connection_reset_exceptions: [Bunny::ConnectionClosedError],
      logger_message_size_limit: 9_500,
      receive_logger: nil,
      publish_logger: nil,
      malformed_logger: nil
    )
      self.group_id = group_id
      self.project_id = project_id
      self.queue_suffix = queue_suffix
      self.hooks = hooks
      self.environment = environment.to_sym
      self.queue_name_conversion = queue_name_conversion
      self.receiving_job_class_callable = receiving_job_class_callable
      self.publishing_job_class_callable = publishing_job_class_callable
      self.default_publishing_job_queue = default_publishing_job_queue
      self.handler_resolver_callable = handler_resolver_callable
      self.exception_notifier = exception_notifier
      self.before_receiving_hooks = before_receiving_hooks
      self.after_receiving_hooks = after_receiving_hooks
      self.skip_publishing_in = skip_publishing_in
      self.use_backoff_handler = use_backoff_handler
      self.backoff_handler_max_retries = backoff_handler_max_retries
      self.connection_reset_max_retries = connection_reset_max_retries
      self.connection_reset_timeout = connection_reset_timeout
      self.connection_reset_exceptions = connection_reset_exceptions
      self.logger_message_size_limit = logger_message_size_limit

      @receive_logger = receive_logger
      @publish_logger = publish_logger
      @malformed_logger = malformed_logger
    end

    def validate!
      raise InvalidConfig, "missing project_id" unless project_id
      raise InvalidConfig, "missing group_id" unless group_id
      raise InvalidConfig, "missing exception_notifier" unless exception_notifier

      unless %i[test development production].include?(environment)
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
      [app_name, queue_suffix].reject { |x| x.nil? || x.empty? }.join(".")
    end

    def receive_logger
      @receive_logger || default_receive_logger
    end

    def publish_logger
      @publish_logger || default_publish_logger
    end

    def malformed_logger
      @malformed_logger || default_malformed_logger
    end

    def environment=(value)
      @environment = value.to_sym
    end

    private

    def default_receive_logger
      Logger.new(Rabbit.root.join("log", "incoming_rabbit_messages.log"))
    end

    def default_publish_logger
      Logger.new(Rabbit.root.join("log", "rabbit.log"))
    end

    def default_malformed_logger
      Logger.new(Rabbit.root.join("log", "malformed_messages.log"))
    end
  end

  extend self

  def config
    @config ||= Config.new
    yield(@config) if block_given?
    @config
  end

  def root
    if defined?(Rails)
      Rails.root
    else
      Pathname.new(Dir.pwd)
    end
  end

  def sneakers_config
    if defined?(Rails)
      Rails.application.config_for("sneakers")
    else
      config = YAML.load_file("config/sneakers.yml", aliases: true)
      config[Rabbit.config.environment.to_s].to_h.symbolize_keys
    end
  end

  def configure
    yield(config)
    config.validate!
  end

  def publish(
    routing_key: nil,
    event: nil,
    data: {},
    exchange_name: [],
    confirm_select: true,
    realtime: false,
    headers: {},
    message_id: nil,
    custom_queue_name: nil
  )
    message = Publishing::Message.new(
      routing_key: routing_key,
      event: event,
      data: data,
      exchange_name: exchange_name,
      confirm_select: confirm_select,
      realtime: realtime,
      headers: headers,
      message_id: message_id,
    )
    job_class = config.publishing_job_class_callable
    publish_job_callable = job_class.is_a?(Proc) ? job_class.call : (job_class || Publishing::Job)
    queue_name = custom_queue_name || default_queue_name

    if message.realtime?
      Publishing.publish(message)
    else
      publish_job_callable.set(queue: queue_name).perform_later(message.to_hash)
    end
  end

  def queue_name(queue, ignore_conversion: false)
    return queue if ignore_conversion
    config.queue_name_conversion ? config.queue_name_conversion.call(queue) : queue
  end

  def default_queue_name(ignore_conversion: false)
    queue_name(config.default_publishing_job_queue, ignore_conversion: ignore_conversion)
  end
end
