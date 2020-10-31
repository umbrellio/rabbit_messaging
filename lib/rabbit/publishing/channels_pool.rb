    class ChannelsPool
      class BaseQueue < Queue
        def initialize(session, max_size)
          @session    = session
          @max_size   = max_size - 1
          @ch_size    = 0
          @create_mon = Mutex.new
        end

        def pop
          create_channel if size == 0

          super
        end

        def push(ch)
          return @ch_size -= 1 unless ch&.open?

          super
        end

        def init_channel
          @create_mon.synchronize do
            return unless @ch_size < @max_size

            push create_channel
            @ch_size += 1

            channel
          end
        end

        protected

        def create_channel
          @session.create_channel
        end
      end

      class ConfirmQueue < BaseQueue
        def create_channel
          @session.create_channel.confirm_select
        end
      end

      def initialize(session)
        max_size = session.channel_max

        @pools = {
          true:  ConfirmQueue.new(session, max_size/2),
          false: BaseQueue.new(session, max_size/2)
        }.freeze
      end

      def with_channel(confirm)
        pool = @pools[confirm]
        ch = pool.pop
        yield ch
      ensure
        pool.push ch
      end
    end
