# frozen_string_literal: true

require "bundler/setup"

Bundler.require(:default, :development)
require "active_job"
require "active_record"

ActiveJob::Base.queue_adapter = :inline
ActiveJob::Base.logger = Logger.new(nil)

Rabbit.config.project_id = "test_project_id"
Rabbit.config.group_id = "test_group_id"
Rabbit.config.exception_notifier = proc { |e| e }
