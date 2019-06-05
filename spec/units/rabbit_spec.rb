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
    }
  end

  before do
    Rabbit.config.queue_name_conversion = -> (queue) { "#{queue}_prepared" }
    Rabbit.config.environment = :production
  end

  shared_examples "publishes" do
    it "publishes" do # rubocop:disable RSpec/ExampleLength
      logger = double("logger")
      bunny = double("bunny")
      channel = double("channel")

      allow(Bunny).to receive_message_chain(:new, :start).and_return(bunny)
      allow(bunny).to receive(:create_channel).and_return(channel)

      allow(Logger).to receive(:new).with(Rails.root.join("log", "rabbit.log")).and_return(logger)
      expect(channel).to receive(:confirm_select).once
      expect(channel).to receive(:wait_for_confirms).and_return(true)
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
        ),
      )

      if expect_to_use_job
        log_line = 'test_group_id.test_project_id.some_exchange / some_queue / ' \
                   'some_event / confirm: {"hello"=>"world"}'

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
        }
        expect_any_instance_of(ActiveJob::ConfiguredJob).to receive(:perform_later)
                                                                .with(perform_params)
                                                                .and_call_original

      else
        log_line = "test_group_id.test_project_id.some_exchange / some_queue / " \
                   "some_event / confirm: {:hello=>:world}"
        expect(Rabbit::Publishing::Job).not_to receive(:perform_later)
      end

      expect(logger).to receive(:debug).with(log_line).once
      described_class.publish(message_options)
    end

    after do
      Thread.current[:bunny_channels] = nil
      Rabbit::Publishing.instance_variable_set(:@client, nil)
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
end
