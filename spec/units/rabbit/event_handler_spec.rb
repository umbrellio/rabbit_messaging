# frozen_string_literal: true

describe Rabbit::EventHandler do
  let(:parent) do
    Class.new(described_class) do
      queue_as :parent_queue
    end
  end

  it "passes the queue down to a subclass" do
    expect(Class.new(parent).queue).to eq(:parent_queue)
  end

  it "keeps ignore_queue_conversion and job configs the subclass assigned before calling super" do
    subclass = Class.new(parent) do
      def self.inherited(child)
        child.ignore_queue_conversion = true
        child.additional_job_configs = { retry: false }

        super
      end
    end

    child = Class.new(subclass)

    expect(child.ignore_queue_conversion).to eq(true)
    expect(child.additional_job_configs).to eq(retry: false)
  end

  it "gives a subclass its own defaults when it assigned nothing" do
    child = Class.new(parent)

    expect(child.ignore_queue_conversion).to eq(false)
    expect(child.additional_job_configs).to eq({})
  end

  it "keeps a queue the subclass assigned before calling super" do
    subclass = Class.new(parent) do
      def self.inherited(child)
        child.queue = :child_queue

        super
      end
    end

    expect(Class.new(subclass).queue).to eq(:child_queue)
  end
end
