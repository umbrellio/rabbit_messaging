# frozen_string_literal: true

module Rabbit
  class Logger
    attr_reader :loggers

    def self.wrap(*loggers)
      new(loggers.flatten)
    end

    def initialize(loggers)
      @loggers = loggers
    end

    %i[
      << log add debug info warn error fatal unknown
      close reopen
      datetime_format= level=
    ].each do |method_name|
      define_method(method_name) do |*args|
        loggers.each { |logger| logger.send(method_name, *args) }
      end
    end
  end
end
