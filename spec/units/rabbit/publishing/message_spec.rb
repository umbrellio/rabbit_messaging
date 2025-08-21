# frozen_string_literal: true

describe Rabbit::Publishing::Message do
  describe "basic_publish_args" do
    subject(:message) { described_class.new(**attributes) }

    context "rounting key not specified" do
      let(:attributes) { Hash[event: :ping] }

      it "raises" do
        expect { message.basic_publish_args }.to raise_error("Routing key not specified")
      end
    end

    context "event not specified" do
      let(:attributes) { Hash[routing_key: :nah] }

      it "raises" do
        expect { message.basic_publish_args }.to raise_error("Event name not specified")
      end
    end

    context "valid message" do
      let(:attributes) do
        {
          event: :ping,
          routing_key: :nah,
          data: { foo: :bar },
          exchange_name: :fanout,
          headers: { "foo" => "bar" },
          message_id: "super-uuid",
        }
      end

      its(:basic_publish_args) do
        is_expected.to eq [
          { foo: :bar }.to_json, "test_group_id.test_project_id.fanout", "nah",
          {
            mandatory: true,
            persistent: true,
            type: "ping",
            content_type: "application/json",
            app_id: "test_group_id.test_project_id",
            headers: { "foo" => "bar" },
            message_id: "super-uuid",
          }
        ]
      end
    end

    context "IPAddr" do
      let(:attributes) do
        {
          event: :update, routing_key: :nah, data: { ip: IPAddr.new("::1") },
          exchange_name: :fanout
        }
      end

      its(:basic_publish_args) do
        is_expected.to eq [
          %({"ip":"::1"}), "test_group_id.test_project_id.fanout", "nah",
          {
            mandatory: true,
            persistent: true,
            type: "update",
            content_type: "application/json",
            app_id: "test_group_id.test_project_id",
            headers: {},
            message_id: nil,
          }
        ]
      end
    end
  end
end
