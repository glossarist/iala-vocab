# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::ConceptFile do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  let(:path) { File.join(tmpdir, "1-1-000.yaml") }

  def write_minimal_concept(p)
  yaml = <<~YAML
    ---
    id: 1-1-000
    data:
      identifier: 1-1-000
    status: valid
  YAML
  File.write(p, yaml)
end

  describe ".read" do
    it "loads a managed concept from disk" do
      write_minimal_concept(path)
      cf = described_class.read(path)
      expect(cf.managed).to be_a(Glossarist::V3::ManagedConcept)
      expect(cf.managed_id).to eq("1-1-000")
    end

    it "starts non-dirty" do
      write_minimal_concept(path)
      cf = described_class.read(path)
      expect(cf.dirty?).to be(false)
    end
  end

  describe "#add_related" do
    it "appends an edge and marks dirty" do
      write_minimal_concept(path)
      cf = described_class.read(path)
      edge = Glossarist::V3::RelatedConcept.new(
        type: "supersedes",
        ref: Glossarist::V3::ConceptRef.new(source: "urn:test:2022", id: "1-1-000"),
      )
      cf.add_related(edge)
      expect(cf.dirty?).to be(true)
      expect(cf.has_edge?(type: "supersedes",
                          source: "urn:test:2022",
                          id: "1-1-000")).to be(true)
    end

    it "does not duplicate identical edges" do
      write_minimal_concept(path)
      cf = described_class.read(path)
      edge = Glossarist::V3::RelatedConcept.new(
        type: "supersedes",
        ref: Glossarist::V3::ConceptRef.new(source: "urn:test:2022", id: "1-1-000"),
      )
      cf.add_related(edge)
      cf.add_related(edge)
      expect(cf.managed.related.count do |r|
        r.type == "supersedes" && r.ref&.source == "urn:test:2022"
      end).to eq(1)
    end
  end

  describe "#save" do
    it "persists to disk and clears dirty" do
      write_minimal_concept(path)
      cf = described_class.read(path)
      cf.add_related(Glossarist::V3::RelatedConcept.new(
        type: "supersedes",
        ref: Glossarist::V3::ConceptRef.new(source: "urn:test:2022", id: "1-1-000"),
      ))
      expect(cf.save).to be(true)
      expect(cf.dirty?).to be(false)

      restored = described_class.read(path)
      expect(restored.has_edge?(type: "supersedes",
                                source: "urn:test:2022",
                                id: "1-1-000")).to be(true)
    end

    it "is idempotent on re-save with no changes" do
      write_minimal_concept(path)
      cf = described_class.read(path)
      expect(cf.save).to be(false)
    end
  end

  describe ".open" do
    it "auto-saves on block exit when mutated" do
      write_minimal_concept(path)
      described_class.open(path) do |cf|
        cf.add_related(Glossarist::V3::RelatedConcept.new(
          type: "supersedes",
          ref: Glossarist::V3::ConceptRef.new(source: "urn:test:2022", id: "1-1-000"),
        ))
      end
      restored = described_class.read(path)
      expect(restored.has_edge?(type: "supersedes",
                                source: "urn:test:2022",
                                id: "1-1-000")).to be(true)
    end
  end
end