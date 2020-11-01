# frozen_string_literal: true

class ChannelsPool
  class BaseQueue < Queue
    def initialize(session, max_size)
      super()

      @session    = session
      @max_size   = max_size - 1
      @ch_size    = 0
      @create_mon = Mutex.new
    end

    def pop
      add_channel if size.zero?

      super
    end

    def push(ch)
      return @ch_size -= 1 unless ch&.open?

      super
    end

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
      true  => ConfirmQueue.new(session, max_size / 2),
      false => BaseQueue.new(session, max_size / 2),
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
