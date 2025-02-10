# frozen_string_literal: true

require "rabbit"
require "rabbit/receiving"
require "rabbit/receiving/message"
require "rabbit/receiving/handler_resolver"
require "rabbit/receiving/malformed_message"

begin
  require "active_job"

  class Rabbit::Receiving::Job < ActiveJob::Base
    def perform(message, arguments)
      message = Rabbit::Receiving::Message.build(message, arguments)
      handler = Rabbit::Receiving::HandlerResolver.handler_for(message)
      handler.new(message).call
    rescue Rabbit::Receiving::MalformedMessage => error
      raise if Rabbit.config.environment == :test
      Rabbit.config.exception_notifier.call(error)
    end
  end
rescue LoadError
  warn "ActiveJob not found! You will need to define Rabbit::Receiving::Job class by yourself."
end
