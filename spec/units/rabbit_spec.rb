# frozen_string_literal: true

RSpec.describe Rabbit do
  let(:message_options) do
    {
      exchange_name: "some_exchange",
      routing_key: "some_queue",
      event: "some_event",
      data: { hello: :world },
      realtime: realtime,
      headers: { "foo" => "bar" },
      message_id: "uuid",
    }
  end

  before do
    Rabbit.config.queue_name_conversion = -> (queue) { "#{queue}_prepared" }
    Rabbit.config.environment = :production
  end

  shared_examples "publishes" do
    let(:publish_logger)   { double("publish_logger") }
    let(:bunny)            { double("bunny") }
    let(:channel)          { double("channel") }

    before do
      allow(Bunny).to receive_message_chain(:new, :start).and_return(bunny)
      allow(bunny).to receive(:create_channel).and_return(channel)
      allow(bunny).to receive(:channel_max).and_return(10)
      allow(channel).to receive(:open?).and_return(true)

      allow(Rabbit.config).to receive(:publish_logger) { publish_logger }
      allow(Rabbit.config).to receive(:logger_message_size_limit) { 10 }

      expect(channel).to receive(:confirm_select).once
      allow(channel).to receive(:wait_for_confirms).and_return(true)
      expect(channel).to receive(:basic_publish).with(
        { hello: :world }.to_json,
        "test_group_id.test_project_id.some_exchange",
        "some_queue",
        match(
          mandatory: true,
          persistent: true,
          type: "some_event",
          content_type: "application/json",
          app_id: "test_group_id.test_project_id",
          headers: { "foo" => "bar" },
          message_id: "uuid",
        ),
      )
    end

    it "publishes" do
      if expect_to_use_job
        set_params = { queue: "default_prepared" }
        expect(Rabbit::Publishing::Job).to receive(:set).with(set_params).and_call_original
        perform_params = {
          routing_key: "some_queue",
          event: "some_event",
          data: { "hello" => "world" },
          exchange_name: %w[some_exchange],
          confirm_select: true,
          realtime: realtime,
          headers: { "foo" => "bar" },
          message_id: "uuid",
        }
        expect_any_instance_of(ActiveJob::ConfiguredJob)
          .to receive(:perform_later).with(perform_params).and_call_original

      else
        expect(Rabbit::Publishing::Job).not_to receive(:perform_later)
      end

      expect(publish_logger).to receive(:debug).with(<<~MSG.strip)
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar"} / some_event / \
        confirm: {"hello":"
      MSG
      expect(publish_logger).to receive(:debug).with(<<~MSG.strip)
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar"} / some_event / \
        confirm: world"}
      MSG
      described_class.publish(message_options)
    end

    after do
      Thread.current[:bunny_channels] = nil
      Rabbit::Publishing.instance_variable_set(:@pool, nil)
      Rabbit::Publishing.instance_variable_set(:@logger, nil)
    end
  end

  context "retries on connection_reset_exceptions" do
    let(:realtime) { true }
    let(:max_retries) { 2 }
    let(:timeout) { 0.1 }
    let(:publish_logger)   { double("publish_logger") }
    let(:bunny)            { double("bunny") }
    let(:channel)          { double("channel") }

    before do
      allow(Bunny).to receive_message_chain(:new, :start).and_return(bunny)
      allow(bunny).to receive(:create_channel).and_return(channel)
      allow(bunny).to receive(:channel_max).and_return(10)
      allow(channel).to receive(:open?).and_return(true)

      allow(Rabbit.config).to receive(:publish_logger) { publish_logger }

      allow(channel).to receive(:wait_for_confirms).and_return(true)
      allow(channel).to receive(:confirm_select).and_return(true)

      allow(Rabbit.config).to receive(:connection_reset_max_retries).and_return(max_retries)
      allow(Rabbit.config).to receive(:connection_reset_timeout).and_return(timeout)
    end

    after do
      Thread.current[:bunny_channels] = nil
      Rabbit::Publishing.instance_variable_set(:@pool, nil)
      Rabbit::Publishing.instance_variable_set(:@logger, nil)
    end

    it "retries publishing when an exception from connection_reset_exceptions occurs" do
      attempt = 0

      allow(channel).to receive(:basic_publish) do |*args|
        attempt += 1
        raise Bunny::ConnectionClosedError.new(args.to_json) if attempt <= max_retries
      end

      expect(channel).to receive(:basic_publish).exactly(max_retries + 1).times
      expect(publish_logger).to receive(:debug).with(<<~MSG.strip).once
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar"} / some_event / \
        confirm: {"hello":"world"}
      MSG

      expect { described_class.publish(message_options) }.not_to raise_error
    end

    it "raises the last exception after max retries" do
      allow(channel).to receive(:basic_publish).and_raise(Bunny::ConnectionClosedError.new(""))

      expect { described_class.publish(message_options) }
        .to raise_error(Bunny::ConnectionClosedError)
    end
  end

  context "realtime" do
    let(:realtime) { true }
    let(:expect_to_use_job) { false }

    include_examples "publishes"
  end

  context "not realtime" do
    let(:realtime) { false }
    let(:expect_to_use_job) { true }

    include_examples "publishes"
  end

  describe "config" do
    describe "#read_queue" do
      specify { expect(Rabbit.config.read_queue).to eq("test_group_id.test_project_id") }

      context "with nil suffix provided" do
        before { Rabbit.config.queue_suffix = nil }

        specify { expect(Rabbit.config.read_queue).to eq("test_group_id.test_project_id") }
      end

      context "with blank suffix provided" do
        before { Rabbit.config.queue_suffix = "" }

        specify { expect(Rabbit.config.read_queue).to eq("test_group_id.test_project_id") }
      end

      context "with suffix provided" do
        before { Rabbit.config.queue_suffix = "smth" }

        specify { expect(Rabbit.config.read_queue).to eq("test_group_id.test_project_id.smth") }
      end
    end
  end
end
