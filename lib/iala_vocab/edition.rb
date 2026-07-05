# frozen_string_literal: true

module IalaVocab
  # Value object capturing one edition's metadata.
  # Editions are immutable declarations — construct once, never mutate.
  # The single source of truth for "what is an edition" is
  # `EditionSeries::LINEAGE`.
  class Edition
    attr_reader :id, :year, :urn, :status, :ref, :ref_aliases,
                :owner, :source_repo, :tags, :directory, :description

    # rubocop:disable Metrics/ParameterLists
    def initialize(id:, year:, urn:, status:, ref:,
                   ref_aliases: [], owner: "IALA",
                   source_repo: "https://github.com/glossarist/iala-vocab",
                   tags: default_tags, directory: default_directory(id),
                   description: {})
      @id = id
      @year = year
      @urn = urn
      @status = status
      @ref = ref
      @ref_aliases = ref_aliases
      @owner = owner
      @source_repo = source_repo
      @tags = tags
      @directory = directory
      @description = description
    end
    # rubocop:enable Metrics/ParameterLists

    def concepts_dir
      File.join(directory, "concepts")
    end

    def register_path
      File.join(directory, "register.yaml")
    end

    def current?
      status == "current"
    end

    def superseded?
      status == "superseded"
    end

    def urn_alias
      "#{urn}*"
    end

    def ==(other)
      other.is_a?(Edition) && other.id == id
    end

    alias :eql? :==

    def hash
      id.hash
    end

    private

    def default_tags
      %w[maritime aids-to-navigation lighthouse iala dictionary].freeze
    end

    def default_directory(edition_id)
      File.join("datasets", edition_id)
    end
  end
end