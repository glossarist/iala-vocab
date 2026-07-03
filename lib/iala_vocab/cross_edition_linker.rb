# frozen_string_literal: true

module IalaVocab
  # Builds the cross-edition +supersedes+ chain.
  #
  # For each (predecessor, current) pair in +EditionSeries.pairs+,
  # matches concepts by +managed.data.identifier+ and appends a single
  # +supersedes+ edge to the +current+ concept pointing at the
  # +predecessor+ concept of the same id.
  #
  # The chain is one-way (newer → older). The concept-browser derives
  # +superseded_by+ at render time from incoming edges — we do not
  # store the inverse.
  #
  # Idempotent: re-running on already-linked data touches zero files.
  class CrossEditionLinker
    attr_reader :series, :concept_file_class

    def initialize(series: EditionSeries, concept_file_class: ConceptFile)
      @series = series
      @concept_file_class = concept_file_class
    end

    def run!
      stats = { pairs_processed: 0, edges_added: 0, files_saved: 0 }
      series.pairs.each do |predecessor, current|
        pair_stats = link_pair(predecessor, current)
        merge_pair_stats!(stats, pair_stats)
      end
      stats
    end

    private

    def link_pair(predecessor, current)
      stats = { edges_added: 0, files_saved: 0 }
      predecessor_ids = load_identifier_index(predecessor)

      each_concept_in(current) do |cf|
        termid = cf.managed_id
        next unless termid
        next unless predecessor_ids.key?(termid)

        edge = build_supersedes_edge(predecessor, termid)
        next if cf.has_edge?(type: "supersedes",
                             source: predecessor.urn,
                             id: termid)

        cf.add_related(edge)
        if cf.save
          stats[:files_saved] += 1
          stats[:edges_added] += 1
        end
      end

      stats
    end

    def load_identifier_index(edition)
      index = {}
      each_concept_in(edition) do |cf|
        id = cf.managed_id
        index[id] = cf.path if id
      end
      index
    end

    def each_concept_in(edition)
      return to_enum(__method__, edition) unless block_given?

      Dir.glob(File.join(edition.concepts_dir, "*.yaml")).each do |path|
        begin
          yield concept_file_class.read(path)
        rescue => e
          warn "  ERROR reading #{path}: #{e.message}"
        end
      end
    end

    def build_supersedes_edge(predecessor, termid)
      Glossarist::V3::RelatedConcept.new(
        type: "supersedes",
        ref: Glossarist::V3::ConceptRef.new(source: predecessor.urn, id: termid),
      )
    end

    def merge_pair_stats!(stats, pair_stats)
      stats[:pairs_processed] += 1
      stats[:edges_added] += pair_stats[:edges_added]
      stats[:files_saved] += pair_stats[:files_saved]
    end
  end
end