# frozen_string_literal: true

RSpec.describe Rabbit do
  let(:message_options) do
    {
      exchange_name: "some_exchange",
      routing_key: "some_queue",
      event: "some_event",
      data: message_data,
      realtime: realtime,
      headers: { "foo" => "bar", "compress" => compress },
      message_id: "uuid",
    }
  end
  let(:additional_params) { {} }
  let(:compress) { false }
  let(:expected_data_for_publish_job) { { "hello" => "world" } }
  let(:message_data) { { hello: :world } }
  let(:basic_publish_data) { message_data.to_json }
  let(:basic_publish_expected_args) do
    {
      mandatory: true,
      persistent: true,
      type: "some_event",
      content_type: "application/json",
      app_id: "test_group_id.test_project_id",
      headers: { "foo" => "bar", "compress" => compress },
      message_id: "uuid",
    }
  end
  let(:logger_first_part_message) { '{"hello":"...' }
  let(:logger_second_part_message) { '...world"}' }
  let(:logger_message_size_limit) { 10 }

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
      allow(Rabbit.config).to \
        receive(:logger_message_size_limit)
          .and_return(logger_message_size_limit)

      expect(channel).to receive(:confirm_select).once
      allow(channel).to receive(:wait_for_confirms).and_return(true)
      expect(channel).to receive(:basic_publish).with(
        basic_publish_data,
        "test_group_id.test_project_id.some_exchange",
        "some_queue",
        match(basic_publish_expected_args),
      )
    end

    it "publishes" do
      if expect_to_use_job
        set_params = { queue: expected_queue }
        expect(job_class).to receive(:set).with(set_params).and_call_original
        perform_params = {
          routing_key: "some_queue",
          event: "some_event",
          data: expected_data_for_publish_job,
          exchange_name: %w[some_exchange],
          confirm_select: true,
          realtime: realtime,
          headers: { "foo" => "bar", "compress" => compress },
          message_id: "uuid",
        }
        expect_any_instance_of(ActiveJob::ConfiguredJob)
          .to receive(:perform_later).with(perform_params).and_call_original

      else
        expect(job_class).not_to receive(:perform_later)
      end

      # rubocop:disable Layout/LineLength
      expect(publish_logger).to receive(:debug).with(<<~MSG.strip)
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar","compress":#{compress}} / some_event / \
        confirm: #{logger_first_part_message}
      MSG
      expect(publish_logger).to receive(:debug).with(<<~MSG.strip)
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar","compress":#{compress}} / some_event / \
        confirm: #{logger_second_part_message}
      MSG
      # rubocop:enable Layout/LineLength
      described_class.publish(**message_options, **additional_params)
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
    let(:job_class)        { Rabbit::Publishing::Job }

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
      # rubocop:disable Layout/LineLength
      expect(publish_logger).to receive(:debug).with(<<~MSG.strip).once
      test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar","compress":#{compress}} / some_event / \
      confirm: {"hello":"world"}
      MSG
      # rubocop:enable Layout/LineLength

      expect { described_class.publish(**message_options) }.not_to raise_error
    end

    it "raises the last exception after max retries" do
      allow(channel).to receive(:basic_publish).and_raise(Bunny::ConnectionClosedError.new(""))

      expect { described_class.publish(**message_options) }
        .to raise_error(Bunny::ConnectionClosedError)
    end
  end

  context "realtime" do
    let(:realtime) { true }
    let(:expect_to_use_job) { false }
    let(:expected_queue) { "default_prepared" }
    let(:job_class) { Rabbit::Publishing::Job }

    include_examples "publishes"
  end

  context "not realtime" do
    let(:realtime) { false }
    let(:expect_to_use_job) { true }
    let(:expected_queue) { "default_prepared" }
    let(:job_class) { Rabbit::Publishing::Job }

    include_examples "publishes"
  end

  context "with custom job class" do
    let(:realtime) { false }
    let(:expect_to_use_job) { true }
    let(:expected_queue) { "default_prepared" }
    let(:job_class) { Class.new(Rabbit::Publishing::Job) }

    before do
      stub_const("CustomJobClass", job_class)
      allow(Rabbit.config).to receive(:publishing_job_class_callable).and_return(job_class)
    end

    include_examples "publishes"
  end

  context "with custom default_publishing_job_queue" do
    let(:realtime) { false }
    let(:expect_to_use_job) { true }
    let(:job_class) { Rabbit::Publishing::Job }
    let(:default_publishing_job_queue) { :custom_queue }
    let(:expected_queue) { "passed_to_method_queue" }
    let(:additional_params) { { custom_queue_name: "passed_to_method_queue" } }

    before do
      allow(Rabbit.config).to(
        receive(:default_publishing_job_queue).and_return(default_publishing_job_queue),
      )
    end

    include_examples "publishes"
  end

  context "with custom queue name" do
    let(:realtime) { false }
    let(:expect_to_use_job) { true }
    let(:job_class) { Rabbit::Publishing::Job }
    let(:default_publishing_job_queue) { :custom_queue }
    let(:expected_queue) { "custom_queue_prepared" }

    before do
      allow(Rabbit.config).to(
        receive(:default_publishing_job_queue).and_return(default_publishing_job_queue),
      )
    end

    include_examples "publishes"
  end

  context "when data should be compressed" do
    let(:realtime) { false }
    let(:compress) { true }
    let(:expect_to_use_job) { true }
    let(:expected_queue) { "default_prepared" }
    let(:job_class) { Rabbit::Publishing::Job }
    let(:expected_data_for_publish_job) do
      Rabbit::Compressor.dump({ "hello" => "world" }, with_base64: true)
    end
    let(:basic_publish_data) { Rabbit::Compressor.dump(message_data) }
    let(:basic_publish_expected_args) do
      super().merge(content_encoding: "gzip")
    end
    let(:logger_first_part_message) { "message part bytes 15..." }
    let(:logger_second_part_message) { "...message part bytes 6" }
    let(:logger_message_size_limit) { 15 }

    it_behaves_like "publishes"

    context "when data should be sent immediately" do
      let(:realtime) { true }
      let(:expect_to_use_job) { false }

      it_behaves_like "publishes"
    end
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
