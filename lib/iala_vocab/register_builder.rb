# frozen_string_literal: true

module IalaVocab
  # Builds the per-edition `register.yaml` from an `Edition`'s metadata
  # plus the shared section tree.
  class RegisterBuilder
    attr_reader :edition, :sections_tree, :languages

    def initialize(edition:, sections_tree:, languages: %w[eng fra spa deu])
      @edition = edition
      @sections_tree = sections_tree
      @languages = languages
    end

    def to_h
      {
        "schema_type" => "glossarist",
        "schema_version" => "3",
        "id" => edition.id,
        "ref" => edition.ref,
        "year" => edition.year,
        "urn" => edition.urn,
        "status" => edition.status,
        "owner" => edition.owner,
        "source_repo" => edition.source_repo,
        "tags" => edition.tags,
        "languages" => languages.dup,
        "language_order" => languages.dup,
        "ordering" => "systematic",
        "description" => stringify_keys(edition.description),
        "sections" => sections_tree,
      }
    end

    def to_yaml_s
      format_yaml(to_h)
    end

    def write!
      FileUtils.mkdir_p(edition.directory)
      File.write(edition.register_path, to_yaml_s)
      true
    end

    private

    def stringify_keys(hash)
      hash.to_h.transform_keys(&:to_s)
    end

    # Stable key ordering for human-readable register.yaml output.
    def format_yaml(data)
      ordered_keys = %w[
        schema_type schema_version id ref year urn status owner
        source_repo tags languages language_order ordering description about sections
      ]
      ordered = {}
      ordered_keys.each { |k| ordered[k] = data[k] if data.key?(k) }
      (data.keys - ordered_keys).each { |k| ordered[k] = data[k] }
      YAML.dump(ordered)
    end
  end
end