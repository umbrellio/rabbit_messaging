# frozen_string_literal: true

module Rabbit
  module Helper
    def self.generate_message(message_part, parts, index)
      if parts == 1
        message_part
      elsif index.zero?
        "#{message_part}..."
      elsif index == parts - 1
        "...#{message_part}"
      else
        "...#{message_part}..."
      end
    end
  end
end
