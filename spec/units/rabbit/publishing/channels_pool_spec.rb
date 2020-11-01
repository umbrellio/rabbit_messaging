# frozen_string_literal: true

describe Rabbit::Publishing::ChannelsPool do
  let(:instance) { described_class.new session }
  let(:session)  { double("session", create_channel: channel, channel_max: max_size) }
  let(:stub)     { double("stub", call: true) }
  let(:max_size) { 10 }

  describe "#with_channel" do
    subject(:with_channel) { instance.with_channel(confirm, &block) }

    let(:confirm) { true }
    let(:block)   { -> (ch) { stub.call ch } }

    context "when confirm is true" do
      let(:channel) { double("channel", open?: true, confirm_select: true, stub: stub) }

      it "call passed block with channel(win confirmation)" do
        expect(channel).to receive(:confirm_select)
        expect(stub).to receive(:call).with(channel)

        with_channel
      end
    end

    context "when confirm is false" do
      let(:confirm) { false }
      let(:channel) { double("cchannel", open?: true, stub: stub) }

      it "call passed block with specified channel" do
        expect(stub).to receive(:call).with(channel)

        with_channel
      end
    end
  end
end

describe Rabbit::Publishing::ChannelsPool::BaseQueue do
  let(:instance) { described_class.new(session, max_size) }
  let(:session)  { double :session, create_channel: channel }
  let(:channel)  { double :channel, open?: ch_open }
  let(:ch_open)  { true }
  let(:max_size) { 10 }

  describe "#pop" do
    subject(:pop) { instance.pop }

    before do
      instance.push channel
    end

    it "return channel object" do
      expect(pop).to eq(channel)
    end

    context "when queue is empty" do
      before do
        allow(instance).to receive(:size).and_return(0)
      end

      it "call :add_channel" do
        expect(instance).to receive(:add_channel)

        pop
      end
    end
  end

  describe "#push" do
    subject(:push) { instance.push channel }

    it "push channel to queue" do
      expect { push }.to change(instance, :size).by(1)
    end

    context "when channel is closed" do
      let(:ch_open) { false }

      it "decrease @ch_size" do
        expect { push }.to change { instance.instance_variable_get(:@ch_size) }.by(-1)
      end

      it "do not push channel to queue" do
        expect { push }.not_to change(instance, :size)
      end
    end
  end

  describe "#add_channel" do
    subject(:add_channel) { instance.add_channel }

    it "call create_channel" do
      expect(instance).to receive(:create_channel)

      add_channel
    end

    it "push created channel to queue" do
      allow(instance).to receive(:create_channel).and_return(channel)

      expect(instance).to receive(:push).with(channel)

      add_channel
    end

    it "increase :@ch_size" do
      expect { add_channel }.to change { instance.instance_variable_get(:@ch_size) }.by(1)
    end

    context "when current channels size not less than max allowed size" do
      before do
        instance.instance_variable_set(:@ch_size, max_size)
      end

      it "call create_channel" do
        expect(instance).not_to receive(:create_channel)

        add_channel
      end

      it "push created channel to queue" do
        allow(instance).to receive(:create_channel).and_return(channel)

        expect(instance).not_to receive(:push).with(channel)

        add_channel
      end

      it "increase :@ch_size" do
        expect { add_channel }.not_to change { instance.instance_variable_get(:@ch_size) }
      end
    end
  end

  describe "#create_channel" do
    subject(:create_channel) { instance.send(:create_channel) }

    it "create new channel" do
      expect(session).to receive(:create_channel)

      create_channel
    end

    it "return new channel" do
      expect(create_channel).to eq(channel)
    end
  end
end

describe Rabbit::Publishing::ChannelsPool::ConfirmQueue do
  let(:instance) { described_class.new(session, max_size) }
  let(:session)  { double :session, create_channel: channel }
  let(:channel)  { double :channel, open?: ch_open, confirm_select: true }
  let(:ch_open)  { true }
  let(:max_size) { 10 }

  describe "#create_channel" do
    subject(:create_channel) { instance.send(:create_channel) }

    it "create new channel" do
      expect(session).to receive(:create_channel)

      create_channel
    end

    it "return channel" do
      expect(create_channel).to eq(channel)
    end

    it "confirm_select on channel" do
      expect(channel).to receive(:confirm_select)

      create_channel
    end
  end
end
