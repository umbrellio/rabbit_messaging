# frozen_string_literal: true

require "msgpack"
require "zlib"
require "base64"

module Rabbit::Compressor
  Error = Class.new(StandardError)
  UncompressingError = Class.new(Error)

  extend self

  delegate :decode64, :strict_encode64, to: Base64

  def dump(data, msgpack_options: {}, with_base64: false)
    dumped = Zlib::Deflate.deflate(MessagePack.pack(data, msgpack_options))

    return dumped unless with_base64

    strict_encode64(dumped)
  end

  def load(data, msgpack_options: {}, with_base64: false)
    return {} unless data

    data = decode64(data) if with_base64

    MessagePack.unpack(Zlib::Inflate.inflate(data), msgpack_options)
  rescue Zlib::Error, MessagePack::UnpackError => error
    raise UncompressingError, "Unable to uncompress data, #{error}"
  end
end
