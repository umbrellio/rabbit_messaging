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

      expect(publish_logger).to receive(:debug).with(<<~MSG.strip).once
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar"} / some_event / \
        confirm: {"hello":"world"}
      MSG
      described_class.publish(message_options)
    end

    after do
      Thread.current[:bunny_channels] = nil
      Rabbit::Publishing.instance_variable_set(:@pool, nil)
      Rabbit::Publishing.instance_variable_set(:@logger, nil)
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
