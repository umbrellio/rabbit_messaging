# frozen_string_literal: true

require "bundler/setup"

Bundler.require(:default, :development)
require "active_job"
require "active_record"

def Rails.root
  Pathname.new(__dir__).join("..")
end

ActiveJob::Base.queue_adapter = :inline
ActiveJob::Base.logger = Logger.new("/dev/null")

Rabbit.config.project_id = "test_project_id"
Rabbit.config.group_id = "test_group_id"
