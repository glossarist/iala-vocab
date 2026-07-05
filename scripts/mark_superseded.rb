#!/usr/bin/env ruby
# Thin wrapper around IalaVocab::LifecycleMarker#mark_superseded!
# Detects MediaWiki "(Superseded)" pages, marks them, and writes
# forward `supersedes` edges on the active target concepts.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "iala_vocab"

stats = IalaVocab::LifecycleMarker.new.mark_superseded!
puts "Mark superseded:"
stats.each { |k, v| puts "  #{k}: #{v}" }