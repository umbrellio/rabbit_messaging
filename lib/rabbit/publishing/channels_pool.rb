# frozen_string_literal: true

module Rabbit
  module Publishing
    class ChannelsPool
      class BaseQueue < Queue
        def initialize(session, max_size)
          super()

          @session    = session
          @max_size   = max_size - 1
          @ch_size    = 0
          @create_mon = Mutex.new
          @ch_dec_mon = Mutex.new
        end

        def pop
          add_channel if size.zero?

          super
        end
        alias_method :deq, :pop

        def push(channel)
          return @ch_dec_mon.synchronize { @ch_size -= 1 } unless channel&.open?

          super
        end
        alias_method :enq, :push

        def add_channel
          @create_mon.synchronize do
            return unless @ch_size < @max_size

            push create_channel
            @ch_size += 1
          end
        end

        protected

        def create_channel
          @session.create_channel
        end
      end

      class ConfirmQueue < BaseQueue
        def create_channel
          ch = @session.create_channel
          ch.confirm_select

          ch
        end
      end

      def initialize(session)
        max_size = session.channel_max

        @pools = {
          true => ConfirmQueue.new(session, max_size / 2),
          false => BaseQueue.new(session, max_size / 2),
        }.freeze
      end

      def with_channel(confirm)
        pool = @pools[confirm]
        ch = pool.deq
        yield ch
      ensure
        pool.enq ch
      end
    end
  end
end
