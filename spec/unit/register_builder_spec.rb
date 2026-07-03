# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::RegisterBuilder do
  let(:edition) do
    IalaVocab::Edition.new(
      id: "test-edition", year: 2024,
      urn: "urn:test:2024",
      status: "current", ref: "Test Edition",
      description: { eng: "Test description.", fra: "Description française." },
    )
  end

  let(:sections_tree) do
    [{ "id" => "1", "names" => { "eng" => "General" }, "children" => [] }]
  end

  let(:builder) { described_class.new(edition: edition, sections_tree: sections_tree) }

  describe "#to_h" do
    it "includes the required fields" do
      h = builder.to_h
      expect(h).to include("schema_type" => "glossarist")
      expect(h).to include("schema_version" => "3")
      expect(h).to include("id" => "test-edition")
      expect(h).to include("ref" => "Test Edition")
      expect(h).to include("year" => 2024)
      expect(h).to include("urn" => "urn:test:2024")
      expect(h).to include("status" => "current")
      expect(h).to include("owner" => "IALA")
      expect(h).to include("tags")
      expect(h).to include("description")
      expect(h).to include("sections")
    end
  end

  describe "#to_yaml" do
    it "emits valid YAML with key order" do
      yaml = YAML.dump(builder.to_h)
      parsed = YAML.load(yaml, aliases: true) rescue YAML.load(yaml)
      expect(parsed["id"]).to eq("test-edition")
      expect(parsed["description"]["eng"]).to eq("Test description.")

      # Schema keys come before section data
      expect(yaml.index("schema_type")).to be < yaml.index("sections")
    end
  end

  describe "#write!" do
    it "writes register.yaml to the edition directory" do
      Dir.mktmpdir do |dir|
        edition = IalaVocab::Edition.new(
          id: "test-save", year: 2024,
          urn: "urn:test:2024",
          status: "current", ref: "T",
          directory: dir,
        )
        builder = described_class.new(edition: edition, sections_tree: [])
        builder.write!
        expect(File).to exist(File.join(dir, "register.yaml"))
      end
    end
  end
end