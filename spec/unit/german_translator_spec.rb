# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe IalaVocab::GermanTranslator do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  let(:translations_dir) { File.join(tmpdir, "translations", "deu") }

  let(:edition) do
    IalaVocab::Edition.new(
      id: "test-de", year: 2023,
      urn: "urn:test:de", status: "current", ref: "T",
      directory: File.join(tmpdir, "dataset"),
    )
  end

  let(:series) do
    s = Object.new
    ed = edition
    s.define_singleton_method(:all) { [ed] }
    s.define_singleton_method(:find) { |id| id == "test-de" ? ed : nil }
    s
  end

  before do
    # Stub EditionSeries to use our test edition
    stub_const("IalaVocab::EditionSeries", series)

    # Create translation cache
    FileUtils.mkdir_p(translations_dir)
    index = [{
      "title" => "Light/de",
      "english_title" => "Light",
      "page_file" => "deu/light-de.json",
    }]
    File.write(File.join(translations_dir, "index.json"), JSON.dump(index))

    # Create cached page with wikitext containing numeric code
    page = {
      "title" => "Light/de",
      "wikitext" => "'''2-1-000\n\n<big><big><big>Licht</big></big></big>\nMerkmal...",
      "parse" => {
        "text" => '<div class="mw-parser-output"><p>2-1-000</p><big><big><big>Licht</big></big></big><p>Merkmal aller Wahrnehmungen...</p></div>',
      },
    }
    File.write(File.join(translations_dir, "light-de.json"), JSON.dump(page))

    # Create target concept file
    FileUtils.mkdir_p(File.join(edition.concepts_dir))
    managed = Glossarist::V3::ManagedConcept.from_yaml(<<~YAML)
      ---
      id: 2-1-000
      data:
        identifier: 2-1-000
      status: valid
    YAML
    File.write(File.join(edition.concepts_dir, "2-1-000.yaml"), managed.to_yaml)
  end

  it "appends a deu localized doc to the matching concept" do
    translator = described_class.new(
      translations_dir: translations_dir,
      datasets: ["test-de"],
    )
    stats = translator.run!

    expect(stats[:appended]).to eq(1)

    concept = IalaVocab::ConceptFile.read(File.join(edition.concepts_dir, "2-1-000.yaml"))
    deu = concept.localized_in("deu")
    expect(deu).not_to be_nil
    expect(deu.data.language_code).to eq("deu")
    expect(deu.data.terms.first.designation).to eq("Licht")
  end

  it "is idempotent on re-run" do
    translator = described_class.new(
      translations_dir: translations_dir,
      datasets: ["test-de"],
    )
    translator.run!
    stats2 = translator.run!

    # Should still report appended (it replaces in place) but concept count stays 1
    concept = IalaVocab::ConceptFile.read(File.join(edition.concepts_dir, "2-1-000.yaml"))
    deu_docs = concept.localized.select { |lc| lc.data&.language_code == "deu" }
    expect(deu_docs.length).to eq(1)
  end

  it "skips entries in SKIP_TITLES" do
    # Add a TestPage entry
    index = JSON.parse(File.read(File.join(translations_dir, "index.json")))
    index << { "title" => "TestPage/de", "english_title" => "TestPage",
               "page_file" => "deu/testpage-de.json" }
    File.write(File.join(translations_dir, "index.json"), JSON.dump(index))

    translator = described_class.new(
      translations_dir: translations_dir,
      datasets: ["test-de"],
    )
    stats = translator.run!
    expect(stats[:skipped]).to eq(1)
  end
end