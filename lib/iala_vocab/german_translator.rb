# frozen_string_literal: true

module IalaVocab
  # Extracts numeric codes from MediaWiki wikitext, looks up the German
  # translation page for each concept, builds a +V3::LocalizedConcept+
  # for German (using +CitationExtractor+ for the body), and appends it
  # to every concept file that matches the numeric code across all
  # editions in the lineage.
  class GermanTranslator
    attr_reader :translations_dir, :datasets, :skip_titles

    def initialize(translations_dir: "reference-docs/scraped/translations/deu",
                   datasets: EditionSeries.all.map(&:id),
                   skip_titles: ["TestPage"].freeze)
      @translations_dir = translations_dir
      @datasets = datasets
      @skip_titles = skip_titles
    end

    def run!
      stats = { scanned: 0, skipped: 0, no_code: 0, no_target: 0,
                appended: 0, errors: 0 }

      each_translation_entry do |entry|
        stats[:scanned] += 1
        if skip_titles.include?(entry["english_title"])
          stats[:skipped] += 1
          next
        end

        code = extract_numeric_code(entry)
        unless code
          stats[:no_code] += 1
          next
        end

        targets = find_concept_files(code)
        if targets.empty?
          stats[:no_target] += 1
          next
        end

        page_url = build_page_url(entry["title"])
        targets.each do |path|
          append_to_file(path, entry, page_url, code)
          stats[:appended] += 1
        rescue => e
          warn "  ERROR appending to #{path}: #{e.message}"
          stats[:errors] += 1
        end
      end

      stats
    end

    private

    def each_translation_entry
      return to_enum(__method__) unless block_given?

      index.each { |entry| yield entry }
    end

    def index
      @index ||= begin
        path = File.join(translations_dir, "index.json")
        abort "Index not found: #{path}" unless File.exist?(path)
        JSON.parse(File.read(path))
      end
    end

    def extract_numeric_code(entry)
      cached = read_cached_page(entry["page_file"])
      return nil unless cached

      m = cached["wikitext"]&.match(/'''(\d+-\d+-\d+)/)
      m && m[1]
    end

    def read_cached_page(page_file)
      # translations_dir is e.g. "reference-docs/scraped/translations/deu"
      # page_file is e.g. "deu/light-de.json" — resolve relative to parent
      translations_parent = File.dirname(translations_dir)
      path = File.join(translations_parent, page_file)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def find_concept_files(numeric_code)
      datasets.each_with_object([]) do |edition_id, hits|
        edition = IalaVocab::EditionSeries.find(edition_id)
        dir = edition ? edition.concepts_dir : File.join("datasets", edition_id, "concepts")
        path = File.join(dir, "#{numeric_code}.yaml")
        hits << path if File.exist?(path)
      end
    end

    def build_page_url(title)
      "https://www.iala.int/wiki/dictionary/index.php/#{title.tr(' ', '_')}"
    end

    def append_to_file(path, entry, page_url, numeric_code)
      cached = read_cached_page(entry["page_file"])
      return unless cached

      extractor = CitationExtractor.new(cached.dig("parse", "text") || "")
      designation = extract_designation(cached)
      localized = build_localized_model(
        numeric_code, designation, extractor.paragraphs.join("\n\n"),
        extractor.sources, page_url,
      )

      ConceptFile.open(path) { |cf| cf.add_localized(localized) }
    end

    def extract_designation(cached)
      html = cached.dig("parse", "text") || ""
      doc = Nokogiri::HTML(html)
      big = doc.at_css(".mw-parser-output big big big") || doc.at_css("big big big")
      big ? big.text.strip : nil
    end

    # rubocop:disable Metrics/MethodLength
    def build_localized_model(termid, designation, definition_body, citations, page_url)
      sources = [default_source] + citations.map { |c| build_source(c) }

      Glossarist::V3::LocalizedConcept.new(
        id: "#{termid}-deu",
        termid: termid,
        data: Glossarist::V3::ConceptData.new(
          language_code: "deu",
          terms: [Glossarist::Designation::Base.new(
            type: "expression",
            designation: designation || termid,
            normative_status: "preferred",
          )],
          definition: [Glossarist::V3::DetailedDefinition.new(content: definition_body)],
          sources: sources,
          annotations: [Glossarist::V3::DetailedDefinition.new(
            content: "Sourced from #{page_url}",
          )],
        ),
      )
    end
    # rubocop:enable Metrics/MethodLength

    def default_source
      Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        origin: Glossarist::V3::Citation.new(
          ref: Glossarist::V3::Citation::Ref.new(source: "IALA Dictionary"),
        ),
      )
    end

    def build_source(citation)
      src = Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        origin: Glossarist::V3::Citation.new(
          ref: Glossarist::V3::Citation::Ref.new(source: citation[:ref_text]),
        ),
      )
      src.modification = "modified from source" if citation[:modified]
      src
    end
  end
end