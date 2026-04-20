# frozen_string_literal: true

require "rabbit/receiving/malformed_message"

module Rabbit::Receiving
  class Message
    attr_accessor :group_id, :project_id, :message_id, :compress,
                  :event, :arguments, :original_message
    attr_reader :data

    def self.build(message, arguments)
      group_id, project_id = arguments.fetch(:app_id).split(".")

      new(
        group_id: group_id,
        project_id: project_id,
        event: arguments.fetch(:type),
        compress: arguments.dig(:headers, "compress") || false,
        data: message,
        message_id: arguments.fetch(:message_id, nil),
        arguments: arguments,
      )
    end

    def initialize(
      group_id: nil,
      project_id: nil,
      message_id: nil,
      event: nil,
      data: nil,
      arguments: nil,
      original_message: nil,
      compress: false
    )
      self.group_id = group_id
      self.project_id = project_id
      self.message_id = message_id
      self.event = event
      self.compress = compress
      self.data = data unless data.nil?
      self.arguments = arguments
      self.original_message = original_message
    end

    def data=(value)
      self.original_message = value
      parsed = parsed_data(value)
      @data = parsed
    rescue JSON::ParserError => error
      mark_as_malformed!("JSON::ParserError: #{error.message}")
    end

    def mark_as_malformed!(errors = "Error not specified")
      MalformedMessage.raise!(self, errors, caller(1))
    end

    def attributes
      {
        group_id: group_id,
        project_id: project_id,
        message_id: message_id,
        event: event,
        data: data,
        arguments: arguments,
        original_message: original_message,
        compress: compress,
      }
    end

    private

    def parsed_data(value)
      return JSON.parse(value).deep_symbolize_keys unless compress

      Rabbit::Compressor.load(value, msgpack_options: { symbolize_keys: true }, with_base64: true)
    end
  end
end
