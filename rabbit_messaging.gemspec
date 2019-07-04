# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rabbit/version"

Gem::Specification.new do |spec|
  spec.required_ruby_version = ">= 2.3.8"

  spec.name    = "rabbit_messaging"
  spec.version = Rabbit::VERSION
  spec.authors = ["Umbrellio"]
  spec.email   = ["oss@umbrellio.biz"]

  spec.summary     = "Rabbit (Rabbit Messaging)"
  spec.description = "Rabbit (Rabbit Messaging)"
  spec.homepage    = "https://github.com/umbrellio/rabbit_messaging"

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^spec/}) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "bunny", "~> 2.0"
  spec.add_runtime_dependency "exception_notification"
  spec.add_runtime_dependency "lamian"
  spec.add_runtime_dependency "rails", ">= 5.2.2.1", "~> 5.2.2"
  spec.add_runtime_dependency "sneakers", "~> 2.0"
  spec.add_runtime_dependency "tainbox"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "bundler-audit"
  spec.add_development_dependency "coveralls"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-its"
  spec.add_development_dependency "rubocop-config-umbrellio"
  spec.add_development_dependency "simplecov"
end
