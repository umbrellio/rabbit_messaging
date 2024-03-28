# frozen_string_literal: true

RSpec.describe Rabbit::Daemon do
  before do
    allow(app_double).to receive(:config_for).with("sneakers").and_return(sneakers_config)
    allow(runner_double).to receive(:run)
    allow(logger_double).to receive(:dup).and_return(sneaker_logger_double)

    allow(Bunny).to receive(:new).and_return(bunny_double)
    allow(Rails).to receive(:application).and_return(app_double)
    allow(Rails).to receive(:env).and_return("test")

    allow(Sneakers::Runner).to receive(:new).and_return(runner_double)
  end

  let(:app_double) { double(:rails_app) }
  let(:worker_double) { double(:receiving_worker) }
  let(:runner_double) { double(:sneakers_runner) }
  let(:sneaker_logger_double) { double(:sneaker_logger) }
  let(:logger_double) { double(:logger) }
  let(:bunny_double) { double(:bunny) }

  let(:sneakers_config) do
    {
      foo: 1,
      bunny_options: {
        bar: 2,
        log_level: "warn",
      }
    }
  end

  specify do
    expect(Sneakers).to receive(:configure).with(
      connection: bunny_double,
      env: "test",
      exchange_type: :direct,
      exchange: "test_group_id.test_project_id",
      hooks: {},
      supervisor: true,
      daemonize: false,
      exit_on_detach: true,
      log: logger_double,
      foo: 1,
    )

    expect(Bunny).to receive(:new).with(logger: sneaker_logger_double, bar: 2)

    expect(Rabbit::Receiving::Worker).to receive(:from_queue).with(
      "test_group_id.test_project_id",
      handler: SneakersHandlers::ExponentialBackoffHandler,
      max_retries: 6,
      arguments: {
        "x-dead-letter-exchange" => "test_group_id.test_project_id.dlx",
        "x-dead-letter-routing-key" => "test_group_id.test_project_id.dlx",
      },
    )

    expect(sneaker_logger_double).to receive(:level=).with("warn")
    expect(runner_double).to receive(:run)
    Rabbit::Daemon.run(logger: logger_double)
  end
end
