#!/usr/bin/env ruby
# Strips redundant backward lifecycle edges (superseded_by, retired_by)
# from all concept files. Per OIML pattern: only forward edges
# (supersedes, retires) are stored; backward is derived by the
# concept-browser from incoming edges at render time.
#
# Idempotent. Run after mark_superseded.rb / transform_historic.rb
# have been updated to stop emitting backward edges.
#
# Run: `bundle exec ruby scripts/strip_backward_lifecycle_edges.rb`

require "yaml"

BACKWARD_TYPES = %w[superseded_by retired_by].freeze

stripped = 0
files_changed = 0

Dir.glob("datasets/iala-*/concepts/*.yaml").each do |path|
  docs = YAML.load_stream(File.read(path))
  changed = false

  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["related"].is_a?(Array)

    kept = doc["related"].reject do |r|
      type = r.is_a?(Hash) && r["type"]
      if BACKWARD_TYPES.include?(type)
        stripped += 1
        next true
      end
      false
    end

    next if kept.length == doc["related"].length

    doc["related"] = kept
    changed = true
  end

  next unless changed

  File.write(path, docs.map { |d| YAML.dump(d) }.join)
  files_changed += 1
end

puts "Stripped #{stripped} backward lifecycle edges across #{files_changed} files."