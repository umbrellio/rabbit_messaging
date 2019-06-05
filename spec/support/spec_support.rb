# frozen_string_literal: true

RSpec.configure do |config|
  rabbit_original_config = Rabbit.config.dup
  config.after { Rabbit.instance_variable_set(:@config, rabbit_original_config) }
end
