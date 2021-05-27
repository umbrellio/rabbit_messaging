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

      Sneakers.configure(**sneakers_config(logger: logger))
      Sneakers.server = true

      Rabbit.config.validate!
      Receiving::Worker.from_queue(Rabbit.config.read_queue)
      Sneakers::Runner.new([Receiving::Worker]).run
    end

    def config
      Rails.application.config_for("sneakers").symbolize_keys
    end

    def connection
      bunny_config = config.delete(:bunny_options).to_h.symbolize_keys
      Bunny.new(bunny_config)
    end

    private

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
        log: logger,
        **config,
      }
    end
  end
end
