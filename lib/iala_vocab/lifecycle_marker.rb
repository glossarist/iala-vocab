# frozen_string_literal: true

module IalaVocab
  # Marks concepts whose MediaWiki source page ends in `(Superseded)`
  # or `(Discontinued)` with the appropriate lifecycle status and
  # cross-edition `superseded_by`/`retired_by` edges.
  #
  # Distinct from `CrossEditionLinker`: this handles within-edition
  # lifecycle (a concept replaced by ANOTHER concept). The linker
  # handles between-edition lineage (the same concept across editions).
  #
  # Existing scripts `mark_superseded.rb` and `transform_historic.rb`
  # continue to do the heavy lifting; this class is the eventual target
  # home for the shared logic. The class is provided for completeness
  # of the namespace but does not yet own the implementation — see
  # TODO.refactor/04-concept-file-abstraction.md for migration plan.
  class LifecycleMarker
    def initialize(series: EditionSeries, concept_file_class: ConceptFile)
      @series = series
      @concept_file_class = concept_file_class
    end

    # Detects whether a concept's authoritative source link points at
    # a MediaWiki page whose title ends with `(Superseded)`.
    def self.superseded_source?(managed_concept)
      link = managed_concept.sources&.flat_map { |s| s.origin&.link }.compact.first
      !!(link && link.end_with?("_(Superseded)"))
    end

    # Strips ` (Superseded)` from a MediaWiki page title to derive the
    # active replacement title.
    def self.active_title_from(link)
      return nil unless link

      File.basename(URI.parse(link).path)
          .sub(/_\(Superseded\)\z/, "")
          .tr("_", " ")
    end
  end
end