# frozen_string_literal: true

require "bunny/channel"

class Bunny::Channel
  module RabbitExtensions
    def handle_basic_return(*)
      @unconfirmed_set_mutex.synchronize { @only_acks_received = false } # fails confirm_select
      super
    end
  end

  prepend(RabbitExtensions)
end
