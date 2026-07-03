# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::Auditor do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  let(:edition) do
    IalaVocab::Edition.new(
      id: "test-audit", year: 2024,
      urn: "urn:test:audit",
      status: "current", ref: "T",
      directory: tmpdir,
    )
  end

  let(:series) do
    ed = edition
    s = Object.new
    s.define_singleton_method(:all) { [ed] }
    s.define_singleton_method(:pairs) { [].each }
    s
  end

  def write_concept(id:, related: [])
    path = File.join(tmpdir, "concepts", "#{id}.yaml")
    FileUtils.mkdir_p(File.dirname(path))
    doc = {
      "id" => id,
      "data" => { "identifier" => id },
      "related" => related,
    }
    File.write(path, YAML.dump(doc))
    path
  end

  it "passes on a clean single-concept edition" do
    write_concept(id: "1-1-000")
    expect(described_class.new(series: series).run!).to be(true)
  end

  it "fails when termid is missing" do
    path = File.join(tmpdir, "concepts", "blank.yaml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump({ "id" => nil, "data" => {} }))
    auditor = described_class.new(series: series)
    expect(auditor.run!).to be(false)
    expect(auditor.errors).not_to be_empty
  end

  it "fails on duplicate termids" do
    # Two files, same identifier — should be detected as duplicate
    write_concept(id: "1-1-000")
    path = File.join(tmpdir, "concepts", "duplicate.yaml")
    File.write(path, YAML.dump({
      "id" => "1-1-000",
      "data" => { "identifier" => "1-1-000" },
    }))
    auditor = described_class.new(series: series)
    expect(auditor.run!).to be(false)
    expect(auditor.errors.any? { |e| e[:message].include?("duplicate") }).to be(true)
  end

  it "fails when a supersedes ref points at a missing file" do
    # Stub series with a predecessor that has no file
    pred_dir = File.join(tmpdir, "pred")
    predecessor = IalaVocab::Edition.new(
      id: "test-pred", year: 2022,
      urn: "urn:test:pred",
      status: "superseded", ref: "T",
      directory: pred_dir,
    )
    current_dir = File.join(tmpdir, "curr")
    current = IalaVocab::Edition.new(
      id: "test-curr", year: 2024,
      urn: "urn:test:audit",
      status: "current", ref: "T",
      directory: current_dir,
    )
    s = Object.new
    s.define_singleton_method(:all) { [predecessor, current] }
    s.define_singleton_method(:pairs) { [[predecessor, current]].each }

    # current has a concept with a supersedes edge to a non-existent predecessor concept
    curr_path = File.join(current_dir, "concepts", "1-1-000.yaml")
    FileUtils.mkdir_p(File.dirname(curr_path))
    File.write(curr_path, YAML.dump({
      "id" => "1-1-000",
      "data" => { "identifier" => "1-1-000" },
      "related" => [
        { "type" => "supersedes",
          "ref" => { "source" => "urn:test:pred", "id" => "1-1-000" } },
      ],
    }))

    auditor = described_class.new(series: s)
    expect(auditor.run!).to be(false)
    expect(auditor.errors.any? { |e| e[:message].include?("missing file") }).to be(true)
  end
end