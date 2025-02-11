# frozen_string_literal: true

RSpec.describe Rabbit::Daemon do
  before do
    allow(runner_double).to receive(:run)
    allow(logger_double).to receive(:dup).and_return(sneaker_logger_double)
    allow(sneaker_logger_double).to receive(:level=)

    allow(Bunny).to receive(:new).and_return(bunny_double)
    allow(Sneakers).to receive(:configure)

    allow(Sneakers::Runner).to receive(:new).and_return(runner_double)
    allow(Rabbit::Receiving::Worker).to receive(:from_queue)
  end

  let(:worker_double) { double(:receiving_worker) }
  let(:runner_double) { double(:sneakers_runner) }
  let(:sneaker_logger_double) { double(:sneaker_logger) }
  let(:logger_double) { double(:logger) }
  let(:bunny_double) { double(:bunny) }

  it "setups sneakers properly and runs daemon" do
    Rabbit::Daemon.run(logger: logger_double)

    expect(Sneakers).to have_received(:configure).with(
      connection: bunny_double,
      env: :production,
      exchange_type: :direct,
      exchange: "test_group_id.test_project_id",
      hooks: {},
      supervisor: true,
      daemonize: false,
      exit_on_detach: true,
      log: logger_double,
      foo: 1,
    )

    expect(Rabbit::Receiving::Worker)
      .to have_received(:from_queue).with("test_group_id.test_project_id")

    expect(Bunny).to have_received(:new).with(logger: sneaker_logger_double, bar: 2)

    expect(sneaker_logger_double).to have_received(:level=).with("warn")
    expect(runner_double).to have_received(:run)
  end

  context "backoff handler enabled" do
    before { Rabbit.config.use_backoff_handler = true }
    before { Rabbit.config.backoff_handler_max_retries = 25 }
    before { Rabbit.config.queue_suffix = "v2" }

    it "uses handler" do
      Rabbit::Daemon.run(logger: logger_double)

      expect(Rabbit::Receiving::Worker).to have_received(:from_queue).with(
        "test_group_id.test_project_id.v2",
        handler: SneakersHandlers::ExponentialBackoffHandler,
        max_retries: 25,
        arguments: {
          "x-dead-letter-exchange" => "test_group_id.test_project_id.v2.dlx",
          "x-dead-letter-routing-key" => "test_group_id.test_project_id.v2.dlx",
        },
      )
    end
  end
end
