# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe IalaVocab::LifecycleMarker do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  let(:source_edition) do
    IalaVocab::Edition.new(
      id: "test-source", year: 2022,
      urn: "urn:test:source",
      status: "superseded", ref: "S",
      directory: File.join(tmpdir, "source"),
    )
  end

  let(:target_edition) do
    IalaVocab::Edition.new(
      id: "test-target", year: 2023,
      urn: "urn:test:target",
      status: "current", ref: "T",
      directory: File.join(tmpdir, "target"),
    )
  end

  let(:series) do
    s = Object.new
    src = source_edition
    tgt = target_edition
    s.define_singleton_method(:all) { [src, tgt] }
    s
  end

  def write_superseded_concept(edition, termid, source_link)
    FileUtils.mkdir_p(edition.concepts_dir)
    path = File.join(edition.concepts_dir, "#{termid}.yaml")
    File.write(path, <<~YAML)
      ---
      id: #{termid}
      data:
        identifier: #{termid}
      status: valid
      sources:
      - type: authoritative
        origin:
          ref:
            source: IALA Dictionary
          link: #{source_link}
    YAML
    path
  end

  def write_active_concept(edition, termid)
    FileUtils.mkdir_p(edition.concepts_dir)
    path = File.join(edition.concepts_dir, "#{termid}.yaml")
    File.write(path, <<~YAML)
      ---
      id: #{termid}
      data:
        identifier: #{termid}
      status: valid
    YAML
    path
  end

  def stub_title_index(edition, title, numeric_code)
    index_dir = "reference-docs/scraped/editions/#{edition.id}"
    FileUtils.mkdir_p(index_dir)
    File.write(File.join(index_dir, "index.json"), JSON.dump([
      { "title" => title, "numeric_code" => numeric_code },
    ]))
  end

  describe ".superseded_source?" do
    it "returns true when the source link ends in _(Superseded)" do
      yaml = <<~YAML
        ---
        id: x
        data:
          identifier: x
        status: valid
        sources:
        - type: authoritative
          origin:
            ref:
              source: IALA Dictionary
            link: https://example.com/Thing_(Superseded)
      YAML
      managed = Glossarist::V3::ManagedConcept.from_yaml(yaml)
      expect(described_class.superseded_source?(managed)).to be(true)
    end

    it "returns false for normal concepts" do
      yaml = <<~YAML
        ---
        id: x
        data:
          identifier: x
        status: valid
        sources:
        - type: authoritative
          origin:
            ref:
              source: IALA Dictionary
            link: https://example.com/Normal_Thing
      YAML
      managed = Glossarist::V3::ManagedConcept.from_yaml(yaml)
      expect(described_class.superseded_source?(managed)).to be(false)
    end
  end

  describe ".active_title_from" do
    it "strips the (Superseded) suffix and converts underscores to spaces" do
      link = "https://example.com/Geographical_Range_(Superseded)"
      expect(described_class.active_title_from(link)).to eq("Geographical Range")
    end

    it "returns nil for nil input" do
      expect(described_class.active_title_from(nil)).to be_nil
    end
  end

  describe "#mark_superseded!" do
    it "marks the superseded concept and writes a forward edge on the active target" do
      # Source: 2-1-245 in source edition with (Superseded) source link
      write_superseded_concept(source_edition, "2-1-245",
                               "https://iala.int/Geographical_Range_(Superseded)")
      # Target: geographical-range in target edition
      write_active_concept(target_edition, "geographical-range")
      # Title index: "Geographical Range" lives in target edition
      stub_title_index(target_edition, "Geographical Range", "geographical-range")

      marker = described_class.new(series: series)
      stats = marker.mark_superseded!

      expect(stats[:superseded_marked]).to eq(1)
      expect(stats[:edges_added]).to eq(1)

      # Verify source concept marked
      src_path = File.join(source_edition.concepts_dir, "2-1-245.yaml")
      src = IalaVocab::ConceptFile.read(src_path)
      expect(src.managed.status).to eq("superseded")

      # Verify forward edge on target
      tgt_path = File.join(target_edition.concepts_dir, "geographical-range.yaml")
      tgt = IalaVocab::ConceptFile.read(tgt_path)
      expect(tgt.has_edge?(type: "supersedes",
                           source: "urn:test:source",
                           id: "2-1-245")).to be(true)
    end

    it "is idempotent" do
      write_superseded_concept(source_edition, "2-1-245",
                               "https://iala.int/Geographical_Range_(Superseded)")
      write_active_concept(target_edition, "geographical-range")
      stub_title_index(target_edition, "Geographical Range", "geographical-range")

      marker = described_class.new(series: series)
      marker.mark_superseded!
      stats2 = marker.mark_superseded!

      expect(stats2[:superseded_marked]).to eq(0)
      expect(stats2[:edges_added]).to eq(0)
    end

    it "skips concepts without the (Superseded) source link" do
      write_active_concept(source_edition, "1-1-000") # no sources at all
      stats = described_class.new(series: series).mark_superseded!
      expect(stats[:superseded_marked]).to eq(0)
    end
  end
end