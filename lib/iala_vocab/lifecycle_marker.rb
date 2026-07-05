# frozen_string_literal: true

require "uri"

module IalaVocab
  # Detects within-edition lifecycle markers in MediaWiki source pages and
  # writes the appropriate status + forward edges.
  #
  # Two distinct concerns, both triggered by MediaWiki page-title suffixes:
  #
  # * (Superseded) — a concept page that has been replaced by a different
  #   concept. Detected via the authoritative source link ending in
  #   `_(Superseded)`. +mark_superseded!+ walks every concept file in every
  #   edition, sets `status: superseded`, adds a retired date matching the
  #   target edition year, and writes a forward `supersedes` edge on the
  #   active target concept.
  #
  # Distinct from `CrossEditionLinker`: the linker handles between-edition
  # lineage (same concept across cumulative editions). `LifecycleMarker`
  # handles within-edition replacement (one concept replaced by another).
  #
  # Forward-only (OIML pattern): backward `superseded_by` is NOT stored.
  # The concept-browser derives it from incoming `supersedes` edges at
  # render time.
  #
  # (Discontinued) page aggregation is a different domain — multiple
  # retired concepts extracted from a single MediaWiki page. That logic
  # lives in `scripts/transform_historic.rb` and is not absorbed here.
  class LifecycleMarker
    attr_reader :series, :concept_file_class

    def initialize(series: EditionSeries, concept_file_class: ConceptFile)
      @series = series
      @concept_file_class = concept_file_class
    end

    def mark_superseded!
      stats = { scanned: 0, superseded_marked: 0, edges_added: 0,
                missing_target: 0, errors: 0 }
      links = []

      each_concept_file do |edition, path|
        stats[:scanned] += 1
        begin
          link_pair = process_superseded_concept(edition, path, stats)
          links << link_pair if link_pair
        rescue => e
          warn "  ERROR on #{path}: #{e.message}"
          stats[:errors] += 1
        end
      end

      links.each { |link| write_forward_supersedes(link, stats) }
      stats
    end

    # Predicates / helpers exposed for specs and external callers.

    def self.superseded_source?(managed_concept)
      links = managed_concept.sources&.flat_map { |s| s.origin&.link }&.compact
      link = links&.first
      !!(link && link.end_with?("_(Superseded)"))
    end

    def self.active_title_from(link)
      return nil unless link

      File.basename(URI.parse(link).path)
          .sub(/_\(Superseded\)\z/, "")
          .tr("_", " ")
    end

    private

    # Walks every concept file in every edition in the series.
    def each_concept_file
      series.all.each do |edition|
        Dir.glob(File.join(edition.concepts_dir, "*.yaml")).each do |path|
          yield edition, path
        end
      end
    end

    # Loads a concept, detects (Superseded) source, mutates status + dates,
    # saves if changed, and returns a link pair for the forward-edge pass.
    def process_superseded_concept(edition, path, stats)
      concept = concept_file_class.read(path)
      return unless concept && concept.managed

      managed = concept.managed
      return unless self.class.superseded_source?(managed)

      base = self.class.active_title_from(managed.sources&.flat_map { |s| s.origin&.link }.compact.first)
      target = active_target_for(base, edition)
      unless target
        warn "  no active target for #{base.inspect} (in #{edition.id})"
        stats[:missing_target] += 1
        return
      end

      target_edition, target_termid = target
      dirty = false

      if managed.status != "superseded"
        managed.status = "superseded"
        stats[:superseded_marked] += 1
        dirty = true
      end

      target_year = target_edition.year
      if target_year && !has_date?(managed, "retired", target_year.to_s)
        managed.dates ||= []
        managed.dates << Glossarist::V3::ConceptDate.new(
          type: "retired", date: target_year.to_s,
        )
        dirty = true
      end

      return unless dirty

      concept.save!
      { source: edition, source_termid: managed.id,
        target: target_edition, target_termid: target_termid }
    end

    # Writes the forward `supersedes` edge on the active target concept.
    def write_forward_supersedes(link, stats)
      target_path = File.join(link[:target].concepts_dir, "#{link[:target_termid]}.yaml")
      return unless File.exist?(target_path)

      concept = concept_file_class.read(target_path)
      return unless concept && concept.managed

      edge = Glossarist::V3::RelatedConcept.new(
        type: "supersedes",
        ref: Glossarist::V3::ConceptRef.new(
          source: link[:source].urn, id: link[:source_termid],
        ),
      )
      return if concept.has_edge?(type: "supersedes",
                                  source: link[:source].urn,
                                  id: link[:source_termid])

      concept.add_related(edge)
      concept.save!
      stats[:edges_added] += 1
    rescue => e
      warn "  ERROR on forward #{target_path}: #{e.message}"
      stats[:errors] += 1
    end

    # Build an index of (edition, title) → entry by reading cached indices.
    def title_index
      @title_index ||= begin
        hash = {}
        series.all.each do |edition|
          path = "reference-docs/scraped/editions/#{edition.id}/index.json"
          next unless File.exist?(path)
          require "json"
          JSON.parse(File.read(path)).each do |entry|
            (hash[entry["title"]] ||= []) << [edition, entry]
          end
        end
        hash
      end
    end

    def active_target_for(stripped_title, source_edition)
      candidates = title_index[stripped_title] || []
      eligible = candidates.reject { |ed, _| ed == source_edition }
      return nil if eligible.empty?

      latest = eligible.max_by { |ed, _| ed.year || 0 }
      edition = latest.first
      entry = latest.last
      termid = entry["numeric_code"] ||
               entry["title"].downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      [edition, termid]
    end

    def has_date?(managed, type, date)
      return false unless managed.dates

      managed.dates.any? { |d| d.type == type && d.date == date }
    end
  end
end