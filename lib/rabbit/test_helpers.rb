# frozen_string_literal: true

module Rabbit::TestHelpers
  def send_rabbit_message(sender_id, event, data)
    Rabbit::Receiving::Worker.new.work_with_params(data.to_json, {}, type: event, app_id: sender_id)
  end

  def expect_rabbit_message(args, strict: true)
    expectation = if strict
                    args
                  else
                    -> (received_args) { expect(received_args).to match(args) }
                  end
    expect(Rabbit).to receive(:publish).with(expectation).once
  end

  def expect_no_rabbit_messages
    expect(Rabbit).not_to receive(:publish)
  end
end
