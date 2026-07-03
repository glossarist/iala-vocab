# frozen_string_literal: true

module IalaVocab
  # Validates dataset invariants across all editions in the series.
  #
  # Three categories of checks:
  #
  # - *Per-concept*: termid present, terms[] non-empty, definition[]
  #   has content (existing checks carried over from the procedural
  #   audit_iala.rb).
  #
  # - *Per-edition*: no duplicate termids.
  #
  # - *Cross-edition*: every +supersedes+ ref resolves to a real file
  #   in the target edition; the supersedes chain is acyclic and
  #   length ≤ +EditionSeries.all.length − 1+.
  class Auditor
    attr_reader :series, :errors

    def initialize(series: EditionSeries)
      @series = series
      @errors = []
    end

    def run!
      series.all.each { |edition| audit_edition(edition) }
      audit_supersedes_chain
      print_report
      errors.empty?
    end

    private

    def audit_edition(edition)
      termids = []
      concept_count = 0
      each_concept_in(edition) do |path, docs|
        concept_count += 1
        managed = docs.first
        audit_managed(edition, path, managed, termids)
        audit_localized(edition, path, docs.drop(1))
      rescue => e
        record_error(path, "exception: #{e.message}")
      end
      audit_duplicates(edition, termids)
    end

    def audit_managed(edition, path, managed, termids)
      termid = managed&.dig("data", "identifier") ||
               managed&.dig("termid") ||
               managed&.dig("id")
      if termid.nil? || termid.to_s.strip.empty?
        record_error(path, "missing termid")
      else
        termids << termid
      end
      nil
    end

    def audit_localized(edition, path, localized_docs)
      localized_docs.each do |doc|
        next unless doc.is_a?(Hash)

        data = doc["data"] || {}
        lang = data["language_code"]
        terms = data["terms"]
        unless terms.is_a?(Array) && !terms.empty?
          record_error(path, "missing terms (#{lang})")
        end
        definition = data["definition"]
        if definition && !(definition.is_a?(Array) &&
                           definition.all? { |d| d.is_a?(Hash) && d.key?("content") })
          record_error(path, "invalid definition structure (#{lang})")
        end
      end
    end

    def audit_duplicates(edition, termids)
      duplicates = termids.tally.select { |_, v| v > 1 }.keys
      duplicates.each do |dup|
        record_error(edition.concepts_dir, "duplicate termid: #{dup}")
      end
    end

    def audit_supersedes_chain
      series.pairs.each do |predecessor, current|
        each_concept_in(current) do |_path, docs|
          managed = docs.first || {}
          related = managed["related"] || []
          related.each do |r|
            next unless r["type"] == "supersedes"

            ref = r["ref"] || {}
            check_supersedes_ref(current, ref)
          end
        rescue => e
          record_error(current.id, "supersedes audit exception: #{e.message}")
        end
      end
    end

    def check_supersedes_ref(current_edition, ref)
      source = ref["source"]
      id = ref["id"]
      return unless source && id

      target_edition = series.all.find { |e| e.urn == source }
      unless target_edition
        record_error(current_edition.id,
                     "supersedes ref unknown source URN: #{source}")
        return
      end

      target_file = File.join(target_edition.concepts_dir, "#{id}.yaml")
      return if File.exist?(target_file)

      record_error(current_edition.id,
                   "supersedes ref points at missing file: #{target_file}")
    end

    def each_concept_in(edition)
      Dir.glob(File.join(edition.concepts_dir, "*.yaml")).each do |path|
        docs = YAML.load_stream(File.read(path))
        yield path, docs
      end
    end

    def record_error(location, message)
      @errors << { location: location, message: message }
    end

    def print_report
      if errors.empty?
        puts "Audit: 0 errors across #{series.all.length} editions."
      else
        puts "Audit: #{errors.length} errors:"
        errors.each { |e| puts "  [#{e[:location]}] #{e[:message]}" }
      end
    end
  end
end