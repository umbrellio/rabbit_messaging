# frozen_string_literal: true

require_relative "dummy/some_group"

describe "Receiving messages" do
  def work
    worker.work_with_params(message, nil, type: event, app_id: "some_group.some_app")
  end

  let(:worker) { Rabbit::Receiving::Worker.new }
  let(:message) { { hello: "world", foo: "bar" }.to_json }
  let(:event) { "some_successful_event" }

  before { Rabbit.config.queue_name_conversion = -> (queue) { "#{queue}_prepared" } }

  context "job enqueued successfully" do
    context "message is valid" do
      context "handler is found" do
        specify "job performs successfully" do
          expect(ExceptionNotifier).not_to receive(:notify_exception)
          queue = "world_some_successful_event_prepared"
          expect(Rabbit::Receiving::Job).to receive(:set).with(queue: queue).and_call_original

          klass = Rabbit::Handler::SomeGroup::SomeSuccessfulEvent
          expect_any_instance_of(klass).to receive(:call) do |instance|
            expect(instance.hello).to eq("world")
            expect(instance.data).to eq(hello: "world", foo: "bar")
          end

          work
        end

        context "job performs unsuccessfully" do
          let(:event) { "some_unsuccessful_event" }

          it "notifies about exception" do
            expect(Rabbit::Receiving::Job).to receive(:set).with(queue: "custom_prepared")
                                                  .and_call_original
            expect(ExceptionNotifier).to receive(:notify_exception) do |exception|
              expect(exception.message).to eq("Unsuccessful event error")
            end
            work
          end
        end

        context "queue name convertion ignorance" do
          let(:klass) { Rabbit::Handler::SomeGroup::SomeSuccessfulEvent }

          shared_examples "event call" do
            specify "successfully called" do
              klass = Rabbit::Handler::SomeGroup::SomeSuccessfulEvent
              expect_any_instance_of(klass).to receive(:call) do |instance|
                expect(instance.hello).to eq("world")
                expect(instance.data).to eq(hello: "world", foo: "bar")
              end

              work
            end
          end

          context "with ignorance" do
            context "with queue name option (explicitly defined)" do
              before { klass.ignore_queue_conversion = true }

              after  { klass.ignore_queue_conversion = false }

              it "uses original queue name" do
                expect(Rabbit::Receiving::Job).to(
                  receive(:set).with(queue: "world_some_successful_event"),
                )

                work
              end

              include_examples "event call"
            end

            context "without queue name option (implicit :default)" do
              let(:klass) { Rabbit::Handler::SomeGroup::EmptySuccessfulEvent }
              let(:event) { "empty_successful_event" }

              before { klass.ignore_queue_conversion = true }

              after  { klass.ignore_queue_conversion = false }

              it "uses original :default queue name" do
                expect(Rabbit::Receiving::Job).to(
                  receive(:set).with(queue: :default),
                )

                work
              end
            end
          end

          context "without ignorance" do
            before { klass.ignore_queue_conversion = false }

            after  { klass.ignore_queue_conversion = false }

            it "uses calculated queue name" do
              expect(Rabbit::Receiving::Job).to(
                receive(:set).with(queue: "world_some_successful_event_prepared"),
              )

              work
            end

            include_examples "event call"

            context "without queue name option (implicit :default)" do
              let(:klass) { Rabbit::Handler::SomeGroup::EmptySuccessfulEvent }
              let(:event) { "empty_successful_event" }

              before { klass.ignore_queue_conversion = false }

              after  { klass.ignore_queue_conversion = false }

              it "uses original :default queue name" do
                expect(Rabbit::Receiving::Job).to(
                  receive(:set).with(queue: "default_prepared"),
                )

                work
              end
            end
          end

          context "default (false)" do
            it "uses calculated queue name" do
              expect(Rabbit::Receiving::Job).to(
                receive(:set).with(queue: "world_some_successful_event_prepared"),
              )

              work
            end

            include_examples "event call"
          end
        end
      end

      context "handler is not found" do
        let(:event) { "no_such_event" }

        it "notifies about exception" do
          expect(Rabbit::Receiving::Job).to receive(:set).with(queue: "default_prepared")
                                                .and_call_original
          expect(ExceptionNotifier).to receive(:notify_exception) do |exception|
            expect(exception.message).to eq <<~ERROR.squish
              "no_such_event" event from "some_group" group is not supported,
              it requires a "Rabbit::Handler::SomeGroup::NoSuchEvent" class inheriting
              from "Rabbit::EventHandler" to be defined
            ERROR
          end
          work
        end
      end
    end

    context "message is malformed" do
      let(:message) { "invalid_json" }

      it "notifies about exception" do
        expect(Rabbit::Receiving::Job).to receive(:set).with(queue: "default_prepared")
                                              .and_call_original
        expect(ExceptionNotifier).to receive(:notify_exception)
                                         .with(Rabbit::Receiving::MalformedMessage)
        work
      end
    end

    context "custom receiving job" do
      let(:custom_job) { class_double("CustomJob") }

      before do
        Rabbit.config.receiving_job_class_callable = -> { custom_job }
      end

      it "works" do
        expect(Rabbit::Receiving::Job).not_to receive(:set)
        expect(custom_job).to receive(:set).with(queue: "world_some_successful_event_prepared")
        work
      end
    end
  end

  specify "job enqueued unsuccessfully" do
    error = RuntimeError.new("Queueing error")
    job = double("job")
    queue = "world_some_successful_event_prepared"

    allow(Rabbit::Receiving::Job).to receive(:set).with(queue: queue).and_return(job)
    allow(job).to receive(:perform_later).and_raise(error)
    expect(ExceptionNotifier).to receive(:notify_exception).with(error)
    expect(worker).to receive(:requeue!)

    work
  end
end
