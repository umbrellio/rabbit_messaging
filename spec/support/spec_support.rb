# frozen_string_literal: true

RSpec.configure do |config|
  rabbit_original_config = Rabbit.config.deep_dup
  config.before { Rabbit.instance_variable_set(:@config, rabbit_original_config.deep_dup) }
end
