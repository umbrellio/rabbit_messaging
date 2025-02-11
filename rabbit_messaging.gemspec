# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rabbit/version"

Gem::Specification.new do |spec|
  spec.required_ruby_version = ">= 3.0"

  spec.name    = "rabbit_messaging"
  spec.version = Rabbit::VERSION
  spec.authors = ["Umbrellio"]
  spec.email   = ["oss@umbrellio.biz"]

  spec.summary     = "Rabbit (Rabbit Messaging)"
  spec.description = "Rabbit (Rabbit Messaging)"
  spec.homepage    = "https://github.com/umbrellio/rabbit_messaging"

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^spec/}) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bunny", "~> 2.0"
  spec.add_dependency "kicks"
  spec.add_dependency "tainbox"
end
