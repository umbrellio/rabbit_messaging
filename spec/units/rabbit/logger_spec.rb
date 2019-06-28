# frozen_string_literal: true

describe Rabbit::Logger do
  let(:message) { "test message" }

  let(:logger1) { double("logger1") }
  let(:logger2) { double("logger2") }

  let(:rabbit_logger) do
    described_class.wrap(logger1, logger2)
  end

  shared_examples "check method call" do |method_name|
    it ".#{method_name}" do
      expect(logger1).to receive(method_name).with(message).once
      expect(logger2).to receive(method_name).with(message).once

      rabbit_logger.send(method_name, message)
    end
  end

  %i[
    << log add debug info warn error fatal unknown
    close reopen datetime_format= level=
  ].each do |method_name|
    include_examples "check method call", method_name
  end
end
