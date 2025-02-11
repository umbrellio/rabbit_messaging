# frozen_string_literal: true

require "sneakers"
require "lamian"
require "sneakers/runner"

require "rabbit/extensions/bunny/channel"
require "rabbit/receiving/worker"

module Rabbit
  module Daemon
    extend self

    def run(logger: Sneakers.logger)
      unless logger
        logger = Logger.new(Rails.root.join("log", "sneakers.log"))
        logger.level = Logger::DEBUG
        Lamian.extend_logger(logger)
      end

      self.logger = logger

      Sneakers.configure(**sneakers_config(logger: logger))
      Sneakers.server = true

      Rabbit.config.validate!

      Receiving::Worker.from_queue(Rabbit.config.read_queue, **worker_options)
      Sneakers::Runner.new([Receiving::Worker]).run
    end

    def config
      @config ||= Rails.application.config_for("sneakers").symbolize_keys
    end

    def connection
      @connection ||= begin
        bunny_config = config.delete(:bunny_options).to_h.symbolize_keys
        bunny_logger = logger.dup
        bunny_logger.level = bunny_config.delete(:log_level) || :info
        Bunny.new(**bunny_config, logger: bunny_logger)
      end
    end

    private

    attr_accessor :logger

    def sneakers_config(logger:)
      {
        connection: connection,
        env: Rails.env,
        exchange_type: :direct,
        exchange: Rabbit.config.app_name,
        hooks: Rabbit.config.hooks,
        supervisor: true,
        daemonize: false,
        exit_on_detach: true,
        queue_options: { no_declare: true },
        log: logger,
        **config,
      }
    end

    def worker_options
      return {} unless Rabbit.config.use_backoff_handler

      require "sneakers_handlers"

      {
        handler: SneakersHandlers::ExponentialBackoffHandler,
        max_retries: Rabbit.config.backoff_handler_max_retries,
        arguments: {
          "x-dead-letter-exchange" => "#{Rabbit.config.read_queue}.dlx",
          "x-dead-letter-routing-key" => "#{Rabbit.config.read_queue}.dlx",
        },
      }
    end
  end
end
