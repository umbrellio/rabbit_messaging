# frozen_string_literal: true

require_relative "dummy/some_group"

describe "Receiving messages" do
  let(:worker)        { Rabbit::Receiving::Worker.new }
  let(:message)       { { hello: "world", foo: "bar" }.to_json }
  let(:delivery_info) { { exchange: "some exchange", routing_key: "some_key" } }
  let(:arguments)     { { type: event, app_id: "some_group.some_app", message_id: "uuid" } }
  let(:event)         { "some_successful_event" }
  let(:job_class)     { Rabbit::Receiving::Job }
  let(:conversion)    { false }
  let(:handler)       { Rabbit::Handler::SomeGroup::SomeSuccessfulEvent }
  let(:before_hook)   { double("before hook") }
  let(:after_hook)    { double("after hook") }
  let(:message_info)  { arguments.merge(delivery_info.slice(:exchange, :routing_key)) }

  def expect_job_queue_to_be_set
    expect(job_class).to receive(:set).with(queue: queue)
  end

  def expect_some_handler_to_be_called
    expect_any_instance_of(handler).to receive(:call) do |instance|
      expect(instance.hello).to eq("world")
      expect(instance.data).to eq(hello: "world", foo: "bar")
      expect(instance.message_info).to include(message_info)
    end
  end

  def expect_empty_handler_to_be_called
    expect_any_instance_of(handler).to receive(:call) do |instance|
      expect(instance.data).to eq(hello: "world", foo: "bar")
      expect(instance.message_info).to include(message_info)
    end
  end

  # fix
  def expect_notification
    expect(Rabbit.config.exception_notifier).to receive(:call)
  end

  def expect_hooks_to_be_called
    expect(before_hook).to receive(:call).with(message, message_info)
    expect(after_hook).to receive(:call).with(message, message_info)
  end

  before do
    Rabbit.config.queue_name_conversion = -> (queue) { "#{queue}_prepared" }

    Rabbit.config.handler_resolver_callable = nil

    Rabbit.config.before_receiving_hooks = [before_hook]
    Rabbit.config.after_receiving_hooks  = [after_hook]

    allow(job_class).to receive(:set).with(queue: queue).and_call_original

    allow(before_hook).to receive(:call).with(message, message_info)
    allow(after_hook).to receive(:call).with(message, message_info)

    handler.ignore_queue_conversion = conversion
  end

  subject(:run_receive) { worker.work_with_params(message, delivery_info, arguments) }

  shared_examples "check job queue and some handler" do
    specify do
      expect_job_queue_to_be_set
      expect_some_handler_to_be_called
      expect_hooks_to_be_called

      run_receive
    end
  end

  context "job enqueued successfully" do
    context "message is valid" do
      context "handler resolver represent by config" do
        before { Rabbit.config.handler_resolver_callable = -> (_m, _g) { test_handler } }
        after { Rabbit.config.handler_resolver_callable = nil }

        let(:test_handler) do
          Class.new(Rabbit::EventHandler) do
            def self.queue
              :test
            end

            def call; end
          end
        end
        let(:queue) { "test_prepared" }
        let(:event) { "magic_event" }

        it "perform our handler" do
          expect(test_handler).to receive(:new).and_call_original
          expect_any_instance_of(test_handler).to receive(:call) do |inst|
            expect(inst.message.data).to eq(message)
          end
          expect(handler).not_to receive(:new)

          run_receive
        end
      end

      context "handler is found" do
        let(:queue) { "world_some_successful_event_prepared" }

        it "performs job successfully" do
          expect(Rabbit.config.exception_notifier).not_to receive(:call)

          expect_job_queue_to_be_set
          expect_some_handler_to_be_called

          run_receive
        end

        context "job performs unsuccessfully" do
          let(:event) { "some_unsuccessful_event" }
          let(:queue) { "custom_prepared" }

          it "notifies about exception" do
            expect_job_queue_to_be_set

            expect_notification do |exception|
              expect(exception.message).to eq("Unsuccessful event error")
            end

            run_receive
          end
        end

        context "queue name convertion ignorance" do
          context "with ignorance" do
            let(:conversion) { true }

            context "with queue name option (explicitly defined)" do
              let(:queue) { "world_some_successful_event" }

              include_examples "check job queue and some handler"
            end

            context "without queue name option (implicit :default)" do
              let(:handler) { Rabbit::Handler::SomeGroup::EmptySuccessfulEvent }
              let(:event)   { "empty_successful_event" }
              let(:queue)   { :default }

              it "uses original :default queue name" do
                expect_job_queue_to_be_set
                expect_empty_handler_to_be_called
                expect_hooks_to_be_called

                run_receive
              end
            end
          end

          context "without ignorance" do
            let(:conversion) { false }
            let(:queue)      { "world_some_successful_event_prepared" }

            include_examples "check job queue and some handler"

            context "without queue name option (implicit :default)" do
              let(:handler) { Rabbit::Handler::SomeGroup::EmptySuccessfulEvent }
              let(:event)   { "empty_successful_event" }
              let(:queue)   { "default_prepared" }

              it "uses original :default queue name" do
                expect_job_queue_to_be_set
                expect_empty_handler_to_be_called
                expect_hooks_to_be_called

                run_receive
              end
            end
          end

          context "default (false)" do
            let(:queue) { "world_some_successful_event_prepared" }

            include_examples "check job queue and some handler"
          end
        end
      end

      context "handler is not found" do
        let(:event) { "no_such_event" }
        let(:queue) { "default_prepared" }

        let(:error_msg) do
          <<~ERROR.squish
            "no_such_event" event from "some_group" group is not supported,
            it requires a "Rabbit::Handler::SomeGroup::NoSuchEvent" class inheriting
            from "Rabbit::EventHandler" to be defined
          ERROR
        end

        # can't set job, raises unsuppoerted event when tries to determine handler
        it "notifies about exception" do
          expect_notification do |exception|
            expect(exception.message).to eq(error_msg)
          end

          run_receive
        end
      end
    end

    context "message is malformed" do
      let(:message) { "invalid_json" }
      let(:queue)   { "default_prepared" }

      # can't set job, raises malformed message when tries to determine queue name
      it "notifies about exception" do
        expect_notification.with(Rabbit::Receiving::MalformedMessage)
        run_receive
      end
    end

    context "custom receiving job" do
      let(:custom_job_class) { class_double("CustomJobClass") }
      let(:custom_job)       { double("CustomJob") }
      let(:queue)            { "world_some_successful_event_prepared" }

      before do
        allow(Rabbit.config).to receive(:receiving_job_class_callable)
          .and_return(-> (_ctx) { custom_job_class })

        allow(custom_job_class).to receive(:set).with(queue: queue).and_return(custom_job)
        allow(custom_job).to receive(:perform_later)
      end

      it "calls custom job" do
        expect(job_class).not_to receive(:set).with(queue: queue)
        expect(custom_job_class).to receive(:set).with(queue: queue)
        expect(custom_job).to receive(:perform_later)

        run_receive
      end

      it "receiving_job_class_callable receives the full message context" do
        expect(Rabbit.config.receiving_job_class_callable).to receive(:call).with(
          message: message,
          delivery_info: delivery_info,
          arguments: arguments,
        )

        run_receive
      end
    end
  end

  context "job enqueued unsuccessfully" do
    let(:error) { RuntimeError.new("Queueing error") }
    let(:job)   { double("job") }
    let(:queue) { "world_some_successful_event_prepared" }

    before do
      allow(job_class).to receive(:set).with(queue: queue).and_return(job)
      allow(job).to receive(:perform_later).and_raise(error)
    end

    specify do
      expect_notification.with(error)
      expect(worker).to receive(:requeue!)

      run_receive
    end
  end
end
