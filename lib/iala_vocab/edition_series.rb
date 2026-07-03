# frozen_string_literal: true

module IalaVocab
  # Ordered lineage of IALA Dictionary editions.
  #
  # The single source of truth for the edition series. Adding a new edition
  # = appending to +LINEAGE+ (and updating the +status+ of the prior
  # current edition to +"superseded"+). No other code anywhere should
  # hardcode the list of editions or the predecessor/successor pairs.
  #
  # Lineage order is oldest → newest (matches reading direction:
  # "X supersedes its predecessor"). The +current+ edition is the LAST
  # entry whose status is +"current"+.
  module EditionSeries
    LINEAGE = [
      Edition.new(
        id: "iala-1970-89", year: 1989,
        urn: "urn:iala:dictionary:1970-89",
        status: "superseded",
        ref: "IALA Dictionary 1970–1989 Edition",
        description: {
          eng: "Foundational IALA Dictionary edition compiled between 1970 and 1989. " \
               "Superseded by the 2009 Edition. ~2,587 concepts across 12 chapters " \
               "covering general terms, visual aids, audible aids, radio aids, " \
               "reliability, power supplies, civil engineering, floating equipment, " \
               "VTS, e-Navigation, AIS, and heritage.",
          fra: "Édition fondatrice du Dictionnaire IALA compilée entre 1970 et 1989. " \
               "Remplacée par l'édition 2009.",
        },
      ),
      Edition.new(
        id: "iala-2009", year: 2009,
        urn: "urn:iala:dictionary:2009",
        status: "superseded",
        ref: "IALA Dictionary 2009 Edition",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2009 Edition. " \
               "Superseded by the 2012 Revision. ~2,666 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2012", year: 2012,
        urn: "urn:iala:dictionary:2012",
        status: "superseded",
        ref: "IALA Dictionary 2012 Revision",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2012 Revision. " \
               "Superseded by the 2015 Revision. ~2,708 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2015", year: 2015,
        urn: "urn:iala:dictionary:2015",
        status: "superseded",
        ref: "IALA Dictionary 2015 Revision",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2015 Revision. " \
               "Superseded by the 2016 Revision. ~2,709 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2016", year: 2016,
        urn: "urn:iala:dictionary:2016",
        status: "superseded",
        ref: "IALA Dictionary 2016 Revision",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2016 Revision. " \
               "Superseded by the 2017 Revision. ~2,721 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2017", year: 2017,
        urn: "urn:iala:dictionary:2017",
        status: "superseded",
        ref: "IALA Dictionary 2017 Revision",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2017 Revision. " \
               "Superseded by the 2018 Revision. ~2,723 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2018", year: 2018,
        urn: "urn:iala:dictionary:2018",
        status: "superseded",
        ref: "IALA Dictionary 2018 Revision",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2018 Revision. " \
               "Superseded by the 2022 Revision. ~2,751 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2022", year: 2022,
        urn: "urn:iala:dictionary:2022",
        status: "superseded",
        ref: "IALA Dictionary 2022 Revision",
        description: {
          eng: "Cumulative state of the IALA Dictionary as of the 2022 Revision. " \
               "Superseded by the 2023 Revision. ~2,753 concepts.",
        },
      ),
      Edition.new(
        id: "iala-2023", year: 2023,
        urn: "urn:iala:dictionary:2023",
        status: "current",
        ref: "IALA Dictionary 2023 Revision",
        description: {
          eng: "Current edition of the IALA Dictionary reflecting contemporary " \
               "practices in electronic navigation, VTS, AIS, and e-Navigation. " \
               "~2,810 concepts across 12 chapters.",
          fra: "Édition actuelle du Dictionnaire IALA reflétant les pratiques " \
               "contemporaines en navigation électronique, VTS, AIS et e-Navigation.",
          spa: "Edición actual del Diccionario IALA que refleja las prácticas " \
               "contemporáneas en navegación electrónica, VTS, AIS y e-Navegación.",
          deu: "Aktuelle Ausgabe des IALA-Wörterbuchs, das zeitgemäße Praktiken " \
               "in der elektronischen Navigation, VTS, AIS und e-Navigation widerspiegelt.",
        },
      ),
    ].freeze

    def self.all
      LINEAGE
    end

    def self.find(edition_id)
      LINEAGE.find { |e| e.id == edition_id }
    end

    def self.current
      LINEAGE.reverse.find(&:current?) || LINEAGE.last
    end

    def self.predecessor(edition)
      idx = LINEAGE.index(edition)
      return nil if idx.nil? || idx.zero?

      LINEAGE[idx - 1]
    end

    def self.successor(edition)
      idx = LINEAGE.index(edition)
      return nil if idx.nil? || idx == LINEAGE.length - 1

      LINEAGE[idx + 1]
    end

    # Enumerator yielding [predecessor, current] pairs.
    # For LINEAGE of length N, yields N-1 pairs (skips the oldest, which
    # has no predecessor). This is what +CrossEditionLinker+ walks.
    def self.pairs
      return to_enum(:pairs) unless block_given?

      LINEAGE.each_cons(2) { |pair| yield pair }
    end
  end
end