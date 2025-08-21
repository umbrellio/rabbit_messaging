# frozen_string_literal: true

require "rabbit/publishing"

module Rabbit::Publishing
  class Job < ActiveJob::Base
    def perform(message)
      Rabbit::Publishing.publish(Message.new(**message))
    end
  end
end
