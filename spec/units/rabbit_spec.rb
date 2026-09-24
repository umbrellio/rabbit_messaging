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
      allow(Rabbit.config).to receive(:logger_message_size_limit).and_return(10)

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

      if compress
        expect(publish_logger).to receive(:debug).with(expected_log_compressed_message)
      else
        # rubocop:disable Layout/LineLength
        expect(publish_logger).to receive(:debug).with(<<~MSG.strip)
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar","compress":#{compress}} / some_event / \
        confirm: {"hello":"...
        MSG
        expect(publish_logger).to receive(:debug).with(<<~MSG.strip)
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar","compress":#{compress}} / some_event / \
        confirm: ...world"}
        MSG
        # rubocop:enable Layout/LineLength
      end
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

      allow(bunny).to receive(:after_recovery_completed)
      allow(bunny).to receive(:recovering_from_network_failure?).and_return(false)
      allow(bunny).to receive(:close)
    end

    after do
      Thread.current[:bunny_channels] = nil
      Rabbit::Publishing.instance_variable_set(:@pool, nil)
      Rabbit::Publishing.instance_variable_set(:@logger, nil)
    end

    def broker_closed_error
      live_session = Bunny::Session.new
      allow(live_session).to receive_messages(open?: true, send_frame: nil, release_channel_id: nil)
      closed_channel = Bunny::Channel.new(live_session, 1)
      closed_channel.handle_method(
        AMQ::Protocol::Channel::Close.new(404, "NOT_FOUND - no exchange", 60, 40),
      )

      closed_channel_error(closed_channel)
    end

    def network_closed_error(recovering: false)
      session = Bunny::Session.new
      allow(session).to receive_messages(
        open?: recovering, recovering_from_network_failure?: recovering,
      )
      closed_channel = Bunny::Channel.new(session, 1)
      closed_channel.connection_closed!

      closed_channel_error(closed_channel)
    end

    def closed_channel_error(closed_channel)
      closed_channel.basic_publish("", "some_exchange", "some_queue")
    rescue Bunny::ChannelAlreadyClosed => error
      error
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

    it "rebuilds the pool when publishing finds the channel closed along with its connection" do
      attempt = 0

      allow(channel).to receive(:basic_publish) do
        attempt += 1
        raise network_closed_error if attempt <= max_retries
      end
      allow(publish_logger).to receive(:debug)

      expect(Rabbit::Publishing).to receive(:reinitialize_channels_pool)
        .exactly(max_retries).times.and_call_original
      expect(bunny).to receive(:close).with(false).exactly(max_retries).times

      expect { described_class.publish(**message_options) }.not_to raise_error
    end

    it "republishes when waiting for confirms finds the channel closed along with its connection" do
      confirms = 0

      allow(channel).to receive(:wait_for_confirms) do
        confirms += 1
        raise network_closed_error if confirms == 1

        true
      end
      allow(publish_logger).to receive(:debug)

      expect(channel).to receive(:basic_publish).twice
      expect(Rabbit::Publishing).to receive(:reinitialize_channels_pool).once.and_call_original

      expect { described_class.publish(**message_options) }.not_to raise_error
    end

    it "rebuilds the pool when the channel is closed while its connection is recovering" do
      attempt = 0

      allow(channel).to receive(:basic_publish) do
        attempt += 1
        raise network_closed_error(recovering: true) if attempt <= max_retries
      end
      allow(publish_logger).to receive(:debug)

      expect(Rabbit::Publishing).to receive(:reinitialize_channels_pool)
        .exactly(max_retries).times.and_call_original

      expect { described_class.publish(**message_options) }.not_to raise_error
    end

    it "retries once on the same connection when the broker closed the channel" do
      attempt = 0

      allow(channel).to receive(:basic_publish) do
        attempt += 1
        raise broker_closed_error if attempt == 1
      end
      allow(publish_logger).to receive(:debug)

      expect(channel).to receive(:basic_publish).twice
      expect(Rabbit::Publishing).not_to receive(:reinitialize_channels_pool)
      expect(Rabbit::Publishing).not_to receive(:sleep)

      expect { Timeout.timeout(5) { described_class.publish(**message_options) } }
        .not_to raise_error
    end

    it "gives up after one retry when the broker keeps closing the channel" do
      allow(channel).to receive(:basic_publish) { raise broker_closed_error }

      expect(channel).to receive(:basic_publish).twice
      expect(Rabbit::Publishing).not_to receive(:reinitialize_channels_pool)
      expect(Rabbit::Publishing).not_to receive(:sleep)

      expect { Timeout.timeout(5) { described_class.publish(**message_options) } }
        .to raise_error(Bunny::ChannelAlreadyClosed)
    end

    it "does not rebuild a pool another thread has already replaced" do
      stale_pool = Rabbit::Publishing.pool

      Rabbit::Publishing.send(:reinitialize_channels_pool, stale_pool)
      current_pool = Rabbit::Publishing.pool

      expect(Bunny).not_to receive(:new)
      expect(bunny).not_to receive(:close)

      Rabbit::Publishing.send(:reinitialize_channels_pool, stale_pool)

      expect(Rabbit::Publishing.pool).to equal(current_pool)
    end

    it "does not rebuild the pool when it was replaced while publishing on it" do
      replaced = false

      allow(channel).to receive(:basic_publish) do
        unless replaced
          replaced = true
          Rabbit::Publishing.send(:reinitialize_channels_pool, Rabbit::Publishing.pool)
          raise Bunny::ConnectionClosedError.new("")
        end
      end
      allow(publish_logger).to receive(:debug)

      expect { described_class.publish(**message_options) }.not_to raise_error
      expect(Bunny).to have_received(:new).twice
      expect(bunny).to have_received(:close).once
    end

    it "closes a recovering session only once its recovery completes" do
      recovery_callback = nil
      allow(bunny).to receive(:recovering_from_network_failure?).and_return(true)
      allow(bunny).to receive(:after_recovery_completed) { |&block| recovery_callback = block }

      Rabbit::Publishing.send(:reinitialize_channels_pool, Rabbit::Publishing.pool)

      expect(bunny).not_to have_received(:close)

      recovery_callback.call.join

      expect(bunny).to have_received(:close).with(false)
    end

    it "reports a failure to close the old session and still publishes" do
      close_error = Bunny::ClientTimeout.new("close timed out")
      attempt = 0

      allow(bunny).to receive(:close).and_raise(close_error)
      allow(channel).to receive(:basic_publish) do
        attempt += 1
        raise Bunny::ConnectionClosedError.new("") if attempt == 1
      end
      allow(publish_logger).to receive(:debug)

      expect(Rabbit.config.exception_notifier).to receive(:call).with(close_error)

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
    # rubocop:disable Layout/LineLength
    let(:expected_log_compressed_message) do
      <<~MSG.strip
        test_group_id.test_project_id.some_exchange / some_queue / {"foo":"bar","compress":#{compress}} / some_event / \
        confirm: message bytes 21
      MSG
    end
    # rubocop:enable Layout/LineLength

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
