# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::CrossEditionLinker do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  # Build a fake 2-edition series in tmpdir: predecessor + current,
  # each with one matching concept (id "1-1-000").
  let(:predecessor) do
    IalaVocab::Edition.new(
      id: "test-old", year: 2022,
      urn: "urn:test:2022",
      status: "superseded", ref: "Old",
      directory: File.join(tmpdir, "old"),
    )
  end

  let(:current) do
    IalaVocab::Edition.new(
      id: "test-new", year: 2023,
      urn: "urn:test:2023",
      status: "current", ref: "New",
      directory: File.join(tmpdir, "new"),
    )
  end

  # A stub series that yields just our pair, no IALA real data.
  let(:series) do
    pred = predecessor
    curr = current
    s = Object.new
    s.define_singleton_method(:all) { [pred, curr] }
    s.define_singleton_method(:pairs) { [[pred, curr]].each }
    s
  end

  def write_concept(dir, id)
    FileUtils.mkdir_p(File.join(dir, "concepts"))
    path = File.join(dir, "concepts", "#{id}.yaml")
    File.write(path, <<~YAML)
      ---
      id: #{id}
      data:
        identifier: #{id}
      status: valid
    YAML
    path
  end

  it "installs a supersedes edge on the current concept" do
    write_concept(predecessor.directory, "1-1-000")
    new_path = write_concept(current.directory, "1-1-000")

    linker = described_class.new(series: series)
    stats = linker.run!

    expect(stats[:edges_added]).to eq(1)
    expect(stats[:files_saved]).to eq(1)

    restored = IalaVocab::ConceptFile.read(new_path)
    expect(restored.has_edge?(type: "supersedes",
                              source: "urn:test:2022",
                              id: "1-1-000")).to be(true)
  end

  it "is idempotent" do
    write_concept(predecessor.directory, "1-1-000")
    write_concept(current.directory, "1-1-000")

    linker = described_class.new(series: series)
    linker.run!
    stats2 = linker.run!

    expect(stats2[:edges_added]).to eq(0)
    expect(stats2[:files_saved]).to eq(0)
  end

  it "skips concepts that have no predecessor match" do
    write_concept(predecessor.directory, "1-1-000")
    new_path = write_concept(current.directory, "9-9-999") # no match

    linker = described_class.new(series: series)
    stats = linker.run!

    expect(stats[:edges_added]).to eq(0)
    restored = IalaVocab::ConceptFile.read(new_path)
    expect(restored.managed.related || []).to be_empty
  end
end