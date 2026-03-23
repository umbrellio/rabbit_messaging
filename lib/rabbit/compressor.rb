# frozen_string_literal: true

require "msgpack"
require "zlib"

module Rabbit::Compressor
  Error = Class.new(StandardError)
  UncompressingError = Class.new(Error)

  extend self

  def dump(data, msgpack_options: {})
    Zlib::Deflate.deflate(MessagePack.pack(data, msgpack_options))
  end

  def load(data, msgpack_options: {})
    return {} unless data

    MessagePack.unpack(Zlib::Inflate.inflate(data), msgpack_options)
  rescue Zlib::Error, MessagePack::UnpackError => error
    raise UncompressingError, "Unable to uncompress data, #{error}"
  end
end
