#!/usr/bin/env ruby
# One-shot migration: strips the old cross-edition `equivalent` mesh
# (and the `superseded_by`/`related_concept` cross-edition fallbacks)
# that the pre-refactor link_editions.rb produced, then runs the new
# IalaVocab::CrossEditionLinker to install the one-way `supersedes`
# chain.
#
# Idempotent: safe to re-run. Within-edition lifecycle edges
# (retired_by/retires/supersedes from LifecycleMarker) are preserved.
#
# Run: `bundle exec ruby scripts/migrate_equivalent_to_supersedes.rb`

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "iala_vocab"

# Edge types that the old link_editions.rb produced for cross-edition
# relationships. These get stripped before the new chain is installed.
CROSS_EDITION_TYPES_TO_STRIP = %w[equivalent related_concept].freeze

# `superseded_by` edges: only strip if they point ACROSS editions
# (i.e., the source URN is one of our edition URNs). Within-edition
# `superseded_by` (from LifecycleMarker for the (Superseded) page
# case) must be preserved — those point at a different concept WITHIN
# the same edition, not at a sibling edition.
EDITION_URNS = IalaVocab::EditionSeries.all.map(&:urn).to_set

$stripped_total = 0

def strip_cross_edition_edges!(docs)
  changed_in_file = false
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["related"].is_a?(Array)

    kept = doc["related"].reject do |r|
      type = r["type"]
      ref = r["ref"] || {}
      source = ref["source"]

      if CROSS_EDITION_TYPES_TO_STRIP.include?(type) && EDITION_URNS.include?(source)
        $stripped_total += 1
        next true
      end
      if type == "superseded_by" && EDITION_URNS.include?(source)
        $stripped_total += 1
        next true
      end
      false
    end

    if kept.length != doc["related"].length
      doc["related"] = kept
      changed_in_file = true
    end
  end
  changed_in_file
end

files_changed = 0
Dir.glob("datasets/iala-*/concepts/*.yaml").each do |path|
  docs = YAML.load_stream(File.read(path))
  next unless strip_cross_edition_edges!(docs)

  File.write(path, docs.map { |d| YAML.dump(d) }.join)
  files_changed += 1
end

puts "Stripped #{$stripped_total} cross-edition edges across #{files_changed} files."

stats = IalaVocab::CrossEditionLinker.new.run!
puts "CrossEditionLinker stats:"
stats.each { |k, v| puts "  #{k}: #{v}" }