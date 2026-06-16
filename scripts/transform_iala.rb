#!/usr/bin/env ruby
require 'json'
require 'nokogiri'
require 'yaml'
require 'fileutils'

edition = ARGV[0]
unless edition
  puts "Usage: bundle exec ruby scripts/transform_iala.rb <edition_id>"
  exit 1
end

index_path = "reference-docs/editions/#{edition}/index.json"
unless File.exist?(index_path)
  puts "Index not found: #{index_path}"
  exit 1
end

index = JSON.parse(File.read(index_path))
out_dir = "datasets/#{edition}/concepts"
FileUtils.mkdir_p(out_dir)

def sanitize(str)
  str.downcase.gsub(/[^a-z0-9]+/, '-')
end

# Keep track of termids to handle suffixes
seen_termids = Hash.new(0)
processed_pages = {}

# Map lang names to ISO 639-2 codes
LANG_MAP = {
  "español" => "spa",
  "français" => "fra",
  "deutsch" => "deu"
}

# Regexes for IALA wiki paragraph classification. Leading <br>/whitespace
# tolerated because the wiki often precedes Note:/Reference: with a <br>.
NOTE_RE = /\A\s*(?:<br\s*\/?>[\s\n]*)*Note:\s*/i
REFERENCE_RE = /\A\s*(?:<br\s*\/?>[\s\n]*)*Reference:\s*/i
ALT_TERM_RE = /\A\s*(?:<br\s*\/?>[\s\n]*)*Alternative\s+term:\s*/i
MODIFIED_RE = /\(modified\)/i
# "term 1-1-030" or "terms 1-1-030, 1-1-040" patterns used in cross-refs
TERMID_MENTION_RE = /\bterm(?:s)?\s+(\d+-\d+-\d+(?:\s*,\s*\d+-\d+-\d+)*)\b/i
TERMID_ONLY_RE = /\A(\d+-\d+-\d+)\z/

# Pre-scan: build termid → designation index from the edition's index.json.
# Used to convert "term 1-1-030" mentions into {1-1-030, Coast guard station}
# inline-ref syntax that concept-browser auto-resolves into hyperlinks.
designation_index = {}
index.each do |it|
  code = it["numeric_code"]
  title = it["title"]
  next if code.nil? || code.empty? || title.nil?
  designation_index[code] = title
end

# Collect bibliographic references across all concepts; written at end.
bibliography = {}

# Inject {{termid, designation}} inline-ref syntax for any "term X-Y-Z" mention.
# concept-browser's extractInlineRefs dispatches {{...}} mentions by parseMention
# kind; numeric kind → handleNumeric → resolves to same-dataset concept URI.
# (Single-brace {...} requires refPrefixMap config we don't have.)
def inject_termid_refs(text, designation_index)
  text.gsub(TERMID_MENTION_RE) do |match|
    ids_string = $1
    prefix = match =~ /^terms/i ? "terms " : "term "
    ids = ids_string.split(/,\s*/).map(&:strip)
    prefix + ids.map do |id|
      designation = designation_index[id]
      designation ? "{{#{id}, #{designation}}}" : id
    end.join(", ")
  end
end

# Classify a paragraph element as :definition, :note, :reference, :symbol,
# :unit, or :alt_term based on the IALA wiki's paragraph conventions.
def classify_paragraph(text)
  return :note if text =~ NOTE_RE || text =~ /\A\s*(?:<br\s*\/?>[\s\n]*)*Note(?:\s*\d+)?\s*:\s/i
  return :reference if text =~ REFERENCE_RE
  return :symbol if text =~ /\A\s*Symbol\s*:\s/i
  return :unit if text =~ /\A\s*Unit\s*:\s/i
  return :alt_term if text =~ ALT_TERM_RE
  :definition
end

# Normalize a bibliographic reference: collapse whitespace, strip "(modified)"
# marker (returned separately), and strip trailing dots.
def normalize_ref(text)
  cleaned = text.gsub(/\s+/, ' ').strip
  modified = !!(cleaned =~ MODIFIED_RE)
  cleaned = cleaned.sub(/\(modified\)/i, '').strip
  cleaned = cleaned.sub(/\.{1,}\s*\z/, '').strip
  [cleaned, modified]
end

# Convert a Nokogiri element's HTML to text, preserving <img> as markdown
# image refs pointing at our downloaded copies in public/images/iala/.
# Without this, el.text strips <img> entirely and figures go missing.
def element_to_text(el)
  html = el.inner_html
  html = html.gsub(/<img[^>]+src="([^"]+)"[^>]*>/i) do
    src = $1
    basename = src.split('/').last.sub(/\?.*$/, '').sub(/\A\d+px-/, '')
    "![#{basename}](/iala-vocab/images/iala/#{basename})"
  end
  html = html.gsub(/<br\s*\/?>/i, "\n")
  txt = Nokogiri::HTML(html).text
  txt.split("\n").map(&:strip).reject(&:empty?).join("\n").strip
end

# Split paragraphs on inline structural markers — but only when the paragraph
# doesn't itself start with a marker. A paragraph that starts with "Note:" is
# kept whole even if "Reference:" appears mid-text inside it (that mid-text
# Reference is descriptive, not a structural citation).
STRUCTURAL_MARKER_RE = /(?=\s(?:Symbol|Unit|Note(?:\s*\d+)?|Reference|Alternative\s+term)\s*:\s)/i
PARAGRAPH_HEAD_MARKER_RE = /\A\s*(?:<br\s*\/?>[\s\n]*)*(Note(?:\s*\d+)?|Reference|Symbol|Unit|Alternative\s+term)\s*:/i

def split_to_fragments(elements)
  fragments = []
  elements.each do |el|
    txt = element_to_text(el)
    next if txt.empty?
    if txt =~ PARAGRAPH_HEAD_MARKER_RE
      fragments << txt
    else
      sub = txt.split(STRUCTURAL_MARKER_RE).map(&:strip).reject(&:empty?)
      fragments.concat(sub)
    end
  end
  fragments
end

# Strip a leading "N " or "N. " source-list number from note text.
def strip_note_leading_number(text)
  text.sub(/\A\s*\d+\s*(?:\.\s*)?/, '')
end

# Convert parenthetical "(X-Y-Z)" mentions into {{termid, designation}} so
# concept-browser's extractInlineRefs can resolve them as cross-concept links.
def inject_paren_termid_refs(text, designation_index)
  text.gsub(/\((\d+-\d+-\d+)\)/) do
    id = $1
    designation = designation_index[id]
    designation ? "{{#{id}, #{designation}}}" : "(#{id})"
  end
end

# Apply both cross-ref injections in one pass.
def inject_all_refs(text, designation_index)
  inject_paren_termid_refs(inject_termid_refs(text, designation_index), designation_index)
end

index.each do |item|
  title = item["title"]
  next if processed_pages[title]
  
  page_file = item["page_file"]
  
  # If this page was already processed as a langlink, we can skip it, OR
  # we can just process it. But to avoid garbage concepts, let's process it
  # unless we explicitly decide to skip. The instructions say "For each concept..."
  # We will just process everything.
  
  # But let's try to grab langlinks when processing a main page.
  
  cached_path = "reference-docs/editions/#{edition}/#{page_file}"
  next unless File.exist?(cached_path)
  
  page = JSON.parse(File.read(cached_path))
  html = page.dig("parse", "text") || ""
  doc = Nokogiri::HTML(html)
  
  # Extract fields
  numeric_code = item["numeric_code"]
  termid_base = (numeric_code && !numeric_code.empty?) ? numeric_code : sanitize(title)
  
  # Append suffix if needed
  seen_termids[termid_base] += 1
  suffix = seen_termids[termid_base] > 1 ? "-#{seen_termids[termid_base] - 1}" : ""
  termid = "#{termid_base}#{suffix}"
  
  designation = title
  
  # Domains
  section_id = nil
  (item["categories"] || []).each do |cat|
    if cat =~ /^(\d+)\.\d+/
      section_id = $1
      break
    end
  end
  section_id ||= "unknown"
  
  # The "Please note that this is the term as it stands in the original IALA
  # Dictionary edition" disclaimer is intentionally NOT extracted: the same
  # provenance information is already encoded via the cross-edition
  # `related: type: equivalent` link injected by link_editions.rb.
  doc.css("i").each { |i| i.remove if i.text.include?("Please note that this is the term") }

  # Extract langlinks before removing them!
  langlinks = []
  doc.css(".LanguageLinks a").each do |a|
    next if a['class'] && a['class'].include?('selflink')
    target_title = a['title']
    lang_text = a.text.strip
    lang_code = LANG_MAP[lang_text] || "eng"
    next if lang_code == "eng"
    langlinks << { title: target_title, lang: lang_code }
  end

  doc.css(".LanguageLinks").remove
  doc.css(".mw-lingo-tooltip").remove
  doc.css("#toc").remove

  parser_output = doc.css(".mw-parser-output").first || doc
  content_elements = doc.css(".mw-parser-output p, .mw-parser-output ul, .mw-parser-output ol").reject do |el|
    el.ancestors.any? { |a| %w[catlinks LanguageLinks mw-lingo-tooltip].any? { |c| a["class"].to_s.include?(c) } } ||
    el.inner_html.include?("editsection")
  end

  # Drop IALA wiki placeholders that pollute definitions. Note: image-only
  # paragraphs have empty .text but contain <img> — keep those so figures
  # survive (element_to_text converts <img> to markdown image refs).
  content_elements = content_elements.reject do |el|
    txt = el.text.strip
    has_img = !el.css('img').empty?
    (txt.empty? && !has_img) ||
      txt =~ /\A\s*No\s+English\s+term\s*\z/i ||
      (numeric_code && !numeric_code.empty? && txt == numeric_code)
  end

  # Split paragraphs on inline structural markers so each Symbol:/Unit:/Note:/
  # Reference:/Alternative-term: becomes its own fragment for classification.
  fragments = split_to_fragments(content_elements)

  definition_paragraphs = []
  extracted_notes = []
  extracted_refs = [] # Array of [ref_text, modified_bool]
  extracted_symbols = []
  extracted_units = []
  alt_terms = []
  modified_any = false
  fragments.each do |frag|
    case classify_paragraph(frag)
    when :note
      note_text = frag.sub(/\A\s*(?:<br\s*\/?>[\s\n]*)*Note(?:\s*\d+)?\s*:\s*/i, '').strip
      note_text = strip_note_leading_number(note_text)
      note_text = inject_all_refs(note_text, designation_index)
      extracted_notes << { "content" => note_text }
    when :reference
      ref_text = frag.sub(/\A\s*(?:<br\s*\/?>[\s\n]*)*Reference:\s*/i, '')
      ref, mod = normalize_ref(ref_text)
      modified_any ||= mod
      extracted_refs << [ref, mod]
    when :symbol
      sym = frag.sub(/\A\s*Symbol\s*:\s*/i, '').strip
      extracted_symbols << sym
    when :unit
      unit = frag.sub(/\A\s*Unit\s*:\s*/i, '').strip
      extracted_units << unit
    when :alt_term
      alt_terms << frag.sub(ALT_TERM_RE, '').strip
    else
      definition_paragraphs << frag
    end
  end

  # A "(modified)" marker surviving into definition text applies concept-wide.
  if definition_paragraphs.any? { |p| p =~ MODIFIED_RE }
    modified_any = true
    definition_paragraphs = definition_paragraphs.map { |p| p.sub(/\s*\(modified\)\s*/i, '').strip }
  end

  # If every definition paragraph is part of a numbered list (e.g. 1./2./3.),
  # treat each as a separate definition entry — these are homonym senses.
  definition_entries = []
  numbered = definition_paragraphs.all? { |p| p =~ /\A\s*\d+\.\s+/ }
  definition_paragraphs.each do |p|
    txt = numbered ? p.sub(/\A\s*\d+\.\s+/, '').strip : p
    txt = inject_all_refs(txt, designation_index)
    definition_entries << txt
  end
  definition_entries.reject!(&:empty?)
  definition_entries = [title] if definition_entries.empty?

  extracted_refs.each do |ref, _|
    slug = sanitize(ref)
    bibliography[slug] ||= { "reference" => ref }
  end
  
  # Build YAML documents
  docs = []

  # Doc 1: Managed Concept (Glossarist v3 — wrap identifier/domains in data:)
  mc = {
    "id" => termid,
    "data" => {
      "identifier" => termid,
      "domains" => [
        {
          "source" => "urn:iala:dictionary:#{edition}",
          "concept_id" => "section-#{section_id}",
          "ref_type" => "section"
        }
      ]
    },
    "status" => "valid",
    "sources" => [
      {
        "type" => "authoritative",
        "origin" => {
          "ref" => "IALA Dictionary",
          "link" => "https://www.iala.int/wiki/dictionary/index.php/#{title.gsub(' ', '_')}"
        }
      }
    ]
  }
  docs << mc

  # Doc 2: English Localized Concept (Glossarist v3 — language_code in data:)
  eng_lang = "eng"
  if title.end_with?("/es")
    eng_lang = "spa"
  elsif title.end_with?("/fre")
    eng_lang = "fra"
  end

  # Terms: preferred designation from title; admitted from "Alternative term:"
  # paragraphs; symbol designations from "Symbol:" markers (Glossarist v3
  # supports type: symbol alongside expression/abbreviation).
  terms = [
    {
      "type" => "expression",
      "designation" => designation,
      "normative_status" => "preferred"
    }
  ]
  alt_terms.each do |alt|
    terms << {
      "type" => "expression",
      "designation" => alt,
      "normative_status" => "admitted"
    }
  end
  extracted_symbols.each do |sym|
    terms << {
      "type" => "symbol",
      "designation" => sym,
      "normative_status" => "preferred"
    }
  end

  # Sources: IALA Dictionary authoritative + any "Reference: X" bibliographic.
  lc_sources = [
    {
      "type" => "authoritative",
      "origin" => { "ref" => "IALA Dictionary" }
    }
  ]
  extracted_refs.each do |ref, ref_mod|
    src = { "type" => "authoritative", "origin" => { "ref" => ref } }
    src["modification"] = "modified from source" if ref_mod || modified_any
    lc_sources << src
  end

  lc_en = {
    "id" => "#{termid}-#{eng_lang}",
    "termid" => termid,
    "data" => {
      "language_code" => eng_lang
    },
    "terms" => terms,
    "definition" => definition_entries.map { |e| { "content" => e } },
    "sources" => lc_sources
  }
  lc_en["notes"] = extracted_notes unless extracted_notes.empty?
  lc_en["examples"] = extracted_units.map { |u| { "content" => u } } unless extracted_units.empty?
  docs << lc_en
  
  # Process langlinks
  langlinks.each do |ll|
    # Find cached page for ll[:title]
    ll_page_file = "pages/#{ll[:title].downcase.gsub(/[^a-z0-9]+/, '-')}.json"
    ll_cached_path = "reference-docs/editions/#{edition}/#{ll_page_file}"
    next unless File.exist?(ll_cached_path)
    
    ll_page = JSON.parse(File.read(ll_cached_path))
    ll_html = ll_page.dig("parse", "text") || ""
    ll_doc = Nokogiri::HTML(ll_html)
    
    ll_doc.css("i").each { |i| i.remove if i.text.include?("Please note that this is the term") }
    ll_doc.css(".LanguageLinks").remove
    ll_doc.css(".mw-lingo-tooltip").remove
    ll_doc.css("#toc").remove

    ll_parser_output = ll_doc.css(".mw-parser-output").first || ll_doc
    ll_content_elements = ll_doc.css(".mw-parser-output p, .mw-parser-output ul, .mw-parser-output ol").reject do |el|
      el.ancestors.any? { |a| %w[catlinks LanguageLinks mw-lingo-tooltip].any? { |c| a["class"].to_s.include?(c) } } ||
      el.inner_html.include?("editsection")
    end

    # Mirror English-page fragment classification (placeholders, structural
    # marker split, Symbol/Unit extraction, numbered-definition handling).
    ll_fragments = split_to_fragments(ll_content_elements)
    ll_definition_paragraphs = []
    ll_extracted_notes = []
    ll_extracted_refs = []
    ll_extracted_symbols = []
    ll_extracted_units = []
    ll_alt_terms = []
    ll_modified_any = false
    ll_fragments.each do |frag|
      next if frag.empty? || frag =~ /\A\s*No\s+English\s+term\s*\z/i ||
              (numeric_code && !numeric_code.empty? && frag == numeric_code)
      case classify_paragraph(frag)
      when :note
        note_text = frag.sub(/\A\s*(?:<br\s*\/?>[\s\n]*)*Note(?:\s*\d+)?\s*:\s*/i, '').strip
        note_text = strip_note_leading_number(note_text)
        note_text = inject_all_refs(note_text, designation_index)
        ll_extracted_notes << { "content" => note_text }
      when :reference
        ref_text = frag.sub(/\A\s*(?:<br\s*\/?>[\s\n]*)*Reference:\s*/i, '')
        ref, mod = normalize_ref(ref_text)
        ll_modified_any ||= mod
        ll_extracted_refs << [ref, mod]
      when :symbol
        ll_extracted_symbols << frag.sub(/\A\s*Symbol\s*:\s*/i, '').strip
      when :unit
        ll_extracted_units << frag.sub(/\A\s*Unit\s*:\s*/i, '').strip
      when :alt_term
        ll_alt_terms << frag.sub(ALT_TERM_RE, '').strip
      else
        ll_definition_paragraphs << frag
      end
    end

    if ll_definition_paragraphs.any? { |p| p =~ MODIFIED_RE }
      ll_modified_any = true
      ll_definition_paragraphs = ll_definition_paragraphs.map { |p| p.sub(/\s*\(modified\)\s*/i, '').strip }
    end

    ll_numbered = ll_definition_paragraphs.all? { |p| p =~ /\A\s*\d+\.\s+/ }
    ll_definition_entries = ll_definition_paragraphs.map do |p|
      txt = ll_numbered ? p.sub(/\A\s*\d+\.\s+/, '').strip : p
      inject_all_refs(txt, designation_index)
    end.reject(&:empty?)
    ll_definition_entries = [ll[:title]] if ll_definition_entries.empty?

    ll_extracted_refs.each do |ref, _|
      slug = sanitize(ref)
      bibliography[slug] ||= { "reference" => ref }
    end

    ll_terms = [
      {
        "type" => "expression",
        "designation" => ll[:title],
        "normative_status" => "preferred"
      }
    ]
    ll_alt_terms.each do |alt|
      ll_terms << {
        "type" => "expression",
        "designation" => alt,
        "normative_status" => "admitted"
      }
    end
    ll_extracted_symbols.each do |sym|
      ll_terms << {
        "type" => "symbol",
        "designation" => sym,
        "normative_status" => "preferred"
      }
    end

    ll_sources = [
      { "type" => "authoritative", "origin" => { "ref" => "IALA Dictionary" } }
    ]
    ll_extracted_refs.each do |ref, ref_mod|
      src = { "type" => "authoritative", "origin" => { "ref" => ref } }
      src["modification"] = "modified from source" if ref_mod || ll_modified_any
      ll_sources << src
    end

    lc_ll = {
      "id" => "#{termid}-#{ll[:lang]}",
      "termid" => termid,
      "data" => {
        "language_code" => ll[:lang]
      },
      "terms" => ll_terms,
      "definition" => ll_definition_entries.map { |e| { "content" => e } },
      "sources" => ll_sources
    }
    lc_ll["notes"] = ll_extracted_notes unless ll_extracted_notes.empty?
    lc_ll["examples"] = ll_extracted_units.map { |u| { "content" => u } } unless ll_extracted_units.empty?
    docs << lc_ll
    
    # Mark as processed so we don't duplicate it later when iterating index.json
    processed_pages[ll[:title]] = true
  end
  
  # Write YAML
  File.open("#{out_dir}/#{termid}.yaml", "w") do |f|
    docs.each do |d|
      f.puts "---"
      f.puts d.to_yaml.sub(/\A---\n/, "")
    end
  end
end

# Write bibliography.yaml: one entry per distinct "Reference: X" found across
# the edition's concepts. Keyed by slug; concepts cite via the human-readable
# ref text in their sources[].origin.ref — matches oiml-vocab's bibliography
# pattern consumed by concept-browser (generate-data.mjs copies it verbatim
# to public/data/{edition}/bibliography.json).
bib_path = "datasets/#{edition}/bibliography.yaml"
File.open(bib_path, "w") do |f|
  f.puts "---"
  f.puts "# Bibliography of external references cited by #{edition} concepts."
  f.puts "# Auto-extracted from 'Reference: ...' paragraphs on IALA wiki pages."
  bibliography.each do |slug, entry|
    f.puts "#{slug}:"
    entry.each do |k, v|
      f.puts "  #{k}: #{v.to_json}"
    end
  end
end

puts "Processed #{seen_termids.size} concepts for #{edition}"
puts "Wrote bibliography (#{bibliography.size} entries) to #{bib_path}"
