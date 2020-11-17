# frozen_string_literal: true

require "sneakers"

require "rabbit"
require "rabbit/receiving/receive"

class Rabbit::Receiving::Worker
  include Sneakers::Worker

  def work_with_params(message, delivery_info, arguments)
    # args and info have custom rabbit classes, have to convert them to hash
    receive_message(message, delivery_info.to_h, arguments.to_h)
    ack!
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
    requeue!
  end
end
