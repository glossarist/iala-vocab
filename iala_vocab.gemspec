# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "iala_vocab"
  spec.version       = "0.1.0"
  spec.summary       = "IALA Dictionary data pipeline — editions, cross-edition linking, lifecycle markers"
  spec.description   = "Pipeline for building the IALA Dictionary Glossarist Concept Browser datasets from upstream MediaWiki source."
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]
  spec.license       = "CC-BY-4.0"

  spec.files         = Dir["lib/**/*.rb"]
  spec.bindir        = "exe"
  spec.executables   = Dir["exe/*"].map { |f| File.basename(f) }

  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "glossarist", ">= 2.8.18"
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "nokogiri", "~> 1.15"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rake", "~> 13.0"
end