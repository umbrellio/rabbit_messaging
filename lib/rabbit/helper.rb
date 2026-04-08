# frozen_string_literal: true

module Rabbit
  module Helper
    def self.generate_message(message_part, parts, index, compressed: false)
      if parts == 1
        format(message_part, compressed)
      elsif index.zero?
        "#{format(message_part, compressed)}..."
      elsif index == parts - 1
        "...#{format(message_part, compressed)}"
      else
        "...#{format(message_part, compressed)}..."
      end
    end

    def self.format(message_part, compressed)
      return message_part unless compressed

      "message part bytes #{message_part.bytesize}"
    end
  end
end
