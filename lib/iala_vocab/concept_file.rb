# frozen_string_literal: true

module IalaVocab
  # Encapsulates a multi-doc concept YAML file on disk: one
  # +Glossarist::V3::ManagedConcept+ followed by zero or more
  # +Glossarist::V3::LocalizedConcept+ documents.
  #
  # Open/read/write lifecycle with dirty tracking. The block form
  # +ConceptFile.open(path) { |cf| ... }+ auto-saves on block exit
  # iff the file was mutated.
  class ConceptFile
    attr_reader :path, :managed, :localized

    class << self
      # Yields the concept file; saves on block exit iff dirty.
      def open(path)
        cf = read(path)
        yield cf
        cf.save
        cf
      end

      # Reads a concept file from disk. Returns a new instance with
      # +dirty? == false+.
      def read(path)
        docs = YAML.load_stream(File.read(path))
        managed = load_managed(docs)
        localized = load_localized(docs)
        new(path: path, managed: managed, localized: localized)
      end
      alias :load :read

      private

      def load_managed(docs)
        return nil if docs.empty? || docs[0].nil?

        Glossarist::V3::ManagedConcept.from_yaml(docs[0].to_yaml)
      end

      def load_localized(docs)
        docs.drop(1).compact.map do |doc|
          Glossarist::V3::LocalizedConcept.from_yaml(doc.to_yaml)
        end
      end
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(path:, managed:, localized: [])
      @path = path
      @managed = managed
      @localized = localized
      @dirty = false
      @initial_serialization = current_serialization
    end
    # rubocop:enable Metrics/ParameterLists

    def dirty?
      @dirty || current_serialization != @initial_serialization
    end

    def managed_id
      managed&.id || managed&.data&.id
    end

    def localized_in(lang_code)
      localized.find { |lc| lc.data&.language_code == lang_code }
    end

    # Upserts a localized concept by +language_code+. Marks dirty.
    def add_localized(lc)
      lang = lc.data&.language_code
      raise ArgumentError, "localized has no language_code" unless lang

      idx = localized.index { |existing| existing.data&.language_code == lang }
      idx ? localized[idx] = lc : localized.push(lc)
      mark_dirty
    end

    # Appends a related edge unless an identical edge already exists.
    # Identity: (type, ref.source, ref.id). Marks dirty.
    def add_related(edge)
      return if has_edge?(type: edge.type,
                          source: edge.ref&.source,
                          id: edge.ref&.id)

      managed.related ||= []
      managed.related << edge
      mark_dirty
    end

    def has_edge?(type:, source:, id:)
      return false unless managed&.related

      managed.related.any? do |r|
        r.type == type &&
          r.ref&.source == source &&
          r.ref&.id == id
      end
    end

    # Writes to disk iff dirty. Returns true on write, false on skip.
    def save
      return false unless dirty?

      save!
    end

    # Writes to disk unconditionally.
    def save!
      FileUtils.mkdir_p(File.dirname(path))
      parts = [managed.to_yaml]
      parts.concat(localized.map(&:to_yaml))
      File.write(path, parts.join)
      @dirty = false
      @initial_serialization = current_serialization
      true
    end

    private

    def mark_dirty
      @dirty = true
    end

    def current_serialization
      return nil unless managed

      parts = [managed.to_yaml]
      parts.concat(localized.map(&:to_yaml))
      parts.join
    end
  end
end