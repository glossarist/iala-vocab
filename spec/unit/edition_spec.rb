# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::Edition do
  let(:edition) do
    described_class.new(
      id: "iala-test", year: 2024,
      urn: "urn:iala:dictionary:test",
      status: "current", ref: "Test Edition",
    )
  end

  it "exposes immutable attr_readers" do
    expect(edition.id).to eq("iala-test")
    expect(edition.year).to eq(2024)
    expect(edition.urn).to eq("urn:iala:dictionary:test")
    expect(edition.status).to eq("current")
    expect(edition.ref).to eq("Test Edition")
  end

  it "defaults owner to IALA and source_repo to the github URL" do
    expect(edition.owner).to eq("IALA")
    expect(edition.source_repo).to eq("https://github.com/metanorma/iala-vocab")
  end

  it "derives concepts_dir and register_path from id" do
    expect(edition.concepts_dir).to eq("datasets/iala-test/concepts")
    expect(edition.register_path).to eq("datasets/iala-test/register.yaml")
  end

  it "knows current? and superseded?" do
    expect(edition.current?).to be(true)
    expect(edition.superseded?).to be(false)

    old = described_class.new(id: "x", year: 2000, urn: "u", status: "superseded", ref: "r")
    expect(old.current?).to be(false)
    expect(old.superseded?).to be(true)
  end

  it "equals another edition by id" do
    other = described_class.new(id: "iala-test", year: 9999, urn: "other", status: "superseded", ref: "r")
    expect(edition).to eq(other)
    expect(edition.hash).to eq(other.hash)
  end
end