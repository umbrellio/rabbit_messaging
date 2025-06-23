# frozen_string_literal: true

module Rabbit::Handler
  module SomeGroup
    class EmptySuccessfulEvent < Rabbit::EventHandler
      def call; end
    end

    class SomeSuccessfulEvent < Rabbit::EventHandler
      queue_as { |message, arguments| "#{message.data[:hello]}_#{arguments[:type]}" }

      attr_accessor :hello

      def call; end
    end

    class SomeUnsuccessfulEvent < Rabbit::EventHandler
      queue_as :custom

      def call
        raise "Unsuccessful event error"
      end
    end
  end
end
