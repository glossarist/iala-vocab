#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "iala_vocab"

require "json"
require "fileutils"
require "nokogiri"

HISTORIC_INDEX = "reference-docs/scraped/editions/iala-historic/index.json"

def load_indices
  hash = {}
  IalaVocab::EditionSeries.all.each do |edition|
    path = "reference-docs/scraped/editions/#{edition.id}/index.json"
    next unless File.exist?(path)
    JSON.parse(File.read(path)).each { |e| (hash[e["title"]] ||= []) << edition }
  end
  hash
end

INDICES = load_indices.freeze

def active_target_for(stripped_title)
  candidates = INDICES[stripped_title] || []
  return nil if candidates.empty?
  latest = candidates.max_by(&:year)
  idx_path = "reference-docs/scraped/editions/#{latest.id}/index.json"
  idx = JSON.parse(File.read(idx_path))
  entry = idx.find { |e| e["title"] == stripped_title }
  termid = entry && (entry["numeric_code"] || entry["title"].downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, ""))
  [latest, termid]
end

def parse_sections(wikitext)
  sections = []
  current = nil
  wikitext.lines.each do |raw|
    line = raw.chomp
    if (m = line.match(/\A==([^=]+)==\z/))
      current = { heading: m[1].strip, code: nil, body_lines: [] }
      sections << current
    elsif current
      current[:body_lines] << line
    end
  end
  sections
end

def extract_code_and_designation(section)
  body = section[:body_lines].map(&:strip).reject(&:empty?)
  code = nil
  body = body.reject do |line|
    if (m = line.match(/\A'''([\w-]+)'''\z/)) && code.nil?
      code = m[1]
      true
    else
      false
    end
  end
  [code, body]
end

def split_notes(lines)
  notes = []
  defs = []
  alt_designation = nil
  current_chunk = []

  lines.each do |line|
    cleaned = line.gsub(/'''/, "").gsub(/''/, "").strip
    if (m = cleaned.match(/\AAlternative term:\s*(.+)\z/))
      alt_designation = m[1].strip
      next
    end
    if (m = cleaned.match(/\ANote:\s*(.+)\z/))
      notes << m[1].strip
      next
    end
    if cleaned.match?(/\APlease note that this is the term/) ||
       cleaned.match?(/\(VTS\d+\//) ||
       cleaned.match?(/\ACategory:/) ||
       cleaned.match?(/\A\[\[/) ||
       cleaned.match?(/\A\{\{/) ||
       cleaned.empty?
      next
    end
    current_chunk << cleaned
  end

  defs = current_chunk
  [alt_designation, notes, defs]
end

def build_localized_model(termid, designation, alt_designation, definition_text, notes, page_url, original_title)
  terms = [
    Glossarist::Designation::Base.new(
      type: "expression",
      designation: designation,
      normative_status: "preferred",
    ),
  ]
  if alt_designation
    terms << Glossarist::Designation::Base.new(
      type: "expression",
      designation: alt_designation,
      normative_status: "admitted",
    )
  end

  annotations = [
    Glossarist::V3::DetailedDefinition.new(
      content: "Discontinued entry from #{original_title} (#{page_url})",
    ),
  ]
  notes_array = notes.map { |n| Glossarist::V3::DetailedDefinition.new(content: n) }

  Glossarist::V3::LocalizedConcept.new(
    id: "#{termid}-eng",
    termid: termid,
    data: Glossarist::V3::ConceptData.new(
      language_code: "eng",
      terms: terms,
      definition: [Glossarist::V3::DetailedDefinition.new(content: definition_text)],
      notes: notes_array,
      annotations: annotations,
      sources: [
        Glossarist::V3::ConceptSource.new(
          type: "authoritative",
          origin: Glossarist::V3::Citation.new(
            ref: Glossarist::V3::Citation::Ref.new(source: "IALA Dictionary"),
          ),
        ),
      ],
    ),
  )
end

def build_managed_model(termid, source_edition, target_edition, target_termid, page_url)
  managed = Glossarist::V3::ManagedConcept.new(
    id: termid,
    status: "retired",
    related: [],
    sources: [
      Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        origin: Glossarist::V3::Citation.new(
          ref: Glossarist::V3::Citation::Ref.new(source: "IALA Dictionary"),
          link: page_url,
        ),
      ),
    ],
    dates: [
      Glossarist::V3::ConceptDate.new(type: "accepted", date: "1970-1989"),
      Glossarist::V3::ConceptDate.new(type: "retired", date: "2016"),
    ],
  )
  managed.data ||= Glossarist::V3::ManagedConceptData.new
  managed.data.id = termid
  managed.data.domains = [
    Glossarist::ConceptReference.new(
      source: source_edition.urn,
      concept_id: "section-historic",
      ref_type: "section",
    ),
  ]

  # Per OIML pattern: forward `retires` edges live on the active
  # target concept (written by +append_retires_to_target+ below).
  # The backward `retired_by` is NOT stored — the concept-browser
  # derives it from incoming `retires` edges at render time.

  managed
end

def append_retires_to_target(target_edition, target_termid, source_edition, source_termid)
  return unless target_edition && target_termid
  target_path = File.join(target_edition.concepts_dir, "#{target_termid}.yaml")
  return unless File.exist?(target_path)

  concept = IalaVocab::ConceptFile.read(target_path)
  return unless concept && concept.managed
  managed = concept.managed

  edge = Glossarist::V3::RelatedConcept.new(
    type: "retires",
    ref: Glossarist::V3::ConceptRef.new(source: source_edition.urn, id: source_termid),
  )
  return if concept.has_edge?(type: "retires",
                              source: source_edition.urn,
                              id: source_termid)

  concept.add_related(edge)
  concept.save!
end

abort "Historic index not found: #{HISTORIC_INDEX}" unless File.exist?(HISTORIC_INDEX)

index = JSON.parse(File.read(HISTORIC_INDEX))
stats = { scanned: 0, skipped_superseded: 0, discontinued_pages: 0, sections_emitted: 0, no_target: 0, errors: 0 }

index.each do |entry|
  stats[:scanned] += 1
  title = entry["title"]

  if title.end_with?("(Superseded)")
    stats[:skipped_superseded] += 1
    next
  end

  next unless title.end_with?("(Discontinued)")
  stats[:discontinued_pages] += 1

  stripped = title.sub(/\s*\(Discontinued\)\z/, "")
  target = active_target_for(stripped)
  target_edition, target_termid = target || [nil, nil]
  unless target_edition
    warn "  no active target for #{stripped.inspect}"
    stats[:no_target] += 1
  end

  page_path = "reference-docs/scraped/editions/iala-historic/#{entry['page_file']}"
  page = JSON.parse(File.read(page_path))
  wikitext = page["wikitext"] || ""
  page_url = "https://www.iala.int/wiki/dictionary/index.php/#{title.tr(' ', '_')}"

  sections = parse_sections(wikitext)
  sections.each do |section|
    code, body = extract_code_and_designation(section)
    unless code
      warn "  no numeric code in section #{section[:heading].inspect} of #{title}"
      next
    end

    alt_designation, notes, defs = split_notes(body)
    definition_text = defs.join("\n\n")
    next if definition_text.strip.empty?

    designation = section[:heading]
    termid = code
    source_edition = IalaVocab::EditionSeries.find("iala-1970-89")
    suffix = ""
    n = 1
    while File.exist?(File.join(source_edition.concepts_dir, "#{termid}#{suffix}.yaml"))
      n += 1
      suffix = "-#{n}"
    end
    final_termid = "#{termid}#{suffix}"

    managed = build_managed_model(final_termid, source_edition, target_edition, target_termid, page_url)
    localized = build_localized_model(final_termid, designation, alt_designation, definition_text, notes, page_url, title)

    # Both docs via V3 library models — annotations are now supported.
    out_path = File.join(source_edition.concepts_dir, "#{final_termid}.yaml")
    parts = [managed.to_yaml, localized.to_yaml]
    File.write(out_path, parts.join)
    stats[:sections_emitted] += 1

    append_retires_to_target(target_edition, target_termid, source_edition, final_termid)
  end
rescue => e
  warn "  ERROR on #{entry['title']}: #{e.message}"
  stats[:errors] += 1
end

puts "Transform historic:"
stats.each { |k, v| puts "  #{k}: #{v}" }