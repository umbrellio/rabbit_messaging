# frozen_string_literal: true

module Rabbit::Receiving
  class MalformedMessage < StandardError
    attr_accessor :message_model, :errors

    def self.logger
      @logger ||= Rabbit.config.malformed_logger
    end

    def self.raise!(message_model, errors, backtrace = caller(1))
      error = new(message_model, errors)
      logger.error error.message
      raise error, error.message, backtrace
    end

    def initialize(message_model, errors)
      self.message_model = message_model
      self.errors = Array(errors)

      errors_list = Array(errors).map { |e| "  - #{e}" }.join("\n")

      super(<<~MESSAGE)
        Malformed message rejected for following reasons:
        #{errors_list}
        Message: #{message_model.attributes.inspect}
      MESSAGE
    end
  end
end
