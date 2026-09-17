# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::ContentCleaner do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  let(:edition) do
    IalaVocab::Edition.new(
      id: "test-clean", year: 2024,
      urn: "urn:test:clean",
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

  def write_concept(termid, localized_yaml_docs)
    path = File.join(tmpdir, "concepts", "#{termid}.yaml")
    FileUtils.mkdir_p(File.dirname(path))
    docs = [{ "id" => termid, "data" => { "identifier" => termid } }] + localized_yaml_docs
    File.write(path, docs.map { |d| YAML.dump(d) }.join)
    path
  end

  def localized(lang:, designation:, definition:, termid: nil)
    {
      "id" => [termid, lang].compact.join("-"),
      "termid" => termid,
      "data" => {
        "language_code" => lang,
        "terms" => [{ "type" => "expression",
                      "normative_status" => "preferred",
                      "designation" => designation }],
        "definition" => [{ "content" => definition }],
        "sources" => [],
      },
    }
  end

  def read_docs(path)
    YAML.load_stream(File.read(path))
  end

  it "recovers the term from the definition first line and strips it" do
    path = write_concept("2-3-120", [
      localized(lang: "spa", designation: "2-3-120", termid: "2-3-120",
                definition: "Casquillo de bayoneta\n\nCasquillo (tipo B)."),
    ])
    described_class.new(series: series).run!
    docs = read_docs(path)
    expect(docs[1]["data"]["terms"].first["designation"]).to eq("Casquillo de bayoneta")
    expect(docs[1]["data"]["definition"].first["content"]).to eq("Casquillo (tipo B).")
  end

  it "strips language suffixes when no term line is recoverable" do
    path = write_concept("8-4-145", [
      localized(lang: "spa", designation: "Fenders/es", termid: "8-4-145",
                definition: "Defensas.\n\nTérmino alternativo: Fendering"),
    ])
    described_class.new(series: series).run!
    docs = read_docs(path)
    expect(docs[1]["data"]["terms"].first["designation"]).to eq("Fenders")
    expect(docs[1]["data"]["definition"].first["content"]).to eq("Defensas.\n\nTérmino alternativo: Fendering")
  end

  it "strips numeric code lines and term echoes from definitions" do
    path = write_concept("fog-signal", [
      localized(lang: "eng", designation: "Fog signal", termid: "fog-signal",
                definition: "3-1 -030\n\nFog signal\n\nSound signal to warn ships."),
    ])
    described_class.new(series: series).run!
    docs = read_docs(path)
    expect(docs[1]["data"]["definition"].first["content"]).to eq("Sound signal to warn ships.")
  end

  it "keeps the cleanest doc when a language is duplicated" do
    path = write_concept("hazard-2-", [
      localized(lang: "fra", designation: "Hazard (2)/fr", termid: "hazard-2-",
                definition: "Danger\n\nDanger signifie toute situation."),
      localized(lang: "fra", designation: "Danger", termid: "hazard-2-",
                definition: "Danger signifie toute situation."),
    ])
    described_class.new(series: series).run!
    fra_docs = read_docs(path).drop(1).select { |d| d["data"]["language_code"] == "fra" }
    expect(fra_docs.size).to eq(1)
    expect(fra_docs.first["data"]["terms"].first["designation"]).to eq("Danger")
  end

  it "deletes junk concepts and scrubs dangling supersedes edges" do
    edge = { "type" => "supersedes",
             "ref" => { "source" => "urn:test:clean", "id" => "testpage-de" } }
    keeper = File.join(tmpdir, "concepts", "keeper.yaml")
    FileUtils.mkdir_p(File.dirname(keeper))
    File.write(keeper, YAML.dump({
      "id" => "keeper", "data" => { "identifier" => "keeper" }, "related" => [edge],
    }))
    write_concept("testpage-de", [
      localized(lang: "eng", designation: "TestPage/de", termid: "testpage-de",
                definition: "Language Test Page in GERMAN"),
    ])

    described_class.new(series: series).run!

    expect(File.exist?(File.join(tmpdir, "concepts", "testpage-de.yaml"))).to be(false)
    keeper_docs = YAML.load_stream(File.read(keeper))
    expect(keeper_docs.first["related"].to_a).to eq([])
  end

  it "is idempotent — a second run rewrites nothing and reports no unresolved items" do
    write_concept("2-3-120", [
      localized(lang: "spa", designation: "2-3-120", termid: "2-3-120",
                definition: "Casquillo de bayoneta\n\nCasquillo (tipo B)."),
    ])
    described_class.new(series: series).run!
    first = described_class.new(series: series)
    expect(first.run!).to be(true)
    expect(first.stats[:files_rewritten]).to eq(0)
  end
end
