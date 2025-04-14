# frozen_string_literal: true

require "sneakers"

require "rabbit"
require "rabbit/receiving/receive"

class Rabbit::Receiving::Worker
  include Sneakers::Worker

  def work_with_params(message, delivery_info, arguments)
    attempt = 0
    begin
      # args and info have custom rabbit classes, have to convert them to hash
      receive_message(message, delivery_info.to_h, arguments.to_h)
      ack!
    rescue *Rabbit.config.connection_reset_exceptions => error
      attempt += 1
      if attempt <= Rabbit.config.connection_reset_max_retries
        sleep(Rabbit.config.connection_reset_timeout)
        reinitialize_connection
        retry
      else
        handle_error!(error)
      end
    end
  rescue => error
    handle_error!(error)
  end

  def receive_message(message, delivery_info, arguments)
    Rabbit::Receiving::Receive.new(
      message: message.dup.force_encoding("UTF-8"),
      delivery_info: delivery_info,
      arguments: arguments,
    ).call
  end

  def handle_error!(error)
    raise if Rabbit.config.environment == :test
    Rabbit.config.exception_notifier.call(error)
    # wait to prevent queue overflow
    sleep 1
    requeue!
  end

  def reinitialize_connection
    stop
    @queue.instance_variable_set(:@banny, nil)
    run
  end
end
