#!/usr/bin/env ruby
# Regenerates register.yaml for every edition in IalaVocab::EditionSeries
# using IalaVocab::RegisterBuilder. Idempotent.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "iala_vocab"
require "json"

sections_path = "reference-docs/scraped/sections/section-tree.json"
abort "Sections file not found: #{sections_path}" unless File.exist?(sections_path)

sections_tree = JSON.parse(File.read(sections_path))

IalaVocab::EditionSeries.all.each do |edition|
  builder = IalaVocab::RegisterBuilder.new(edition: edition, sections_tree: sections_tree)
  builder.write!
  puts "  wrote #{edition.register_path}"
end

puts "Generated #{IalaVocab::EditionSeries.all.length} registers."