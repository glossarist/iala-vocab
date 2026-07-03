# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::EditionSeries do
  it "has a frozen LINEAGE constant of 9 editions" do
    expect(described_class::LINEAGE.length).to eq(9)
    expect(described_class::LINEAGE).to be_frozen
  end

  it "orders LINEAGE oldest → newest" do
    years = described_class::LINEAGE.map(&:year)
    expect(years).to eq(years.sort)
  end

  it "has exactly one current edition" do
    current_eds = described_class::LINEAGE.select(&:current?)
    expect(current_eds.length).to eq(1)
    expect(current_eds.first.id).to eq("iala-2023")
  end

  it "marks all non-current editions as superseded" do
    non_current = described_class::LINEAGE.reject(&:current?)
    expect(non_current).to all(satisfy { |e| e.superseded? })
  end

  describe ".find" do
    it "returns the edition by id" do
      expect(described_class.find("iala-2018").year).to eq(2018)
    end

    it "returns nil for unknown id" do
      expect(described_class.find("iala-9999")).to be_nil
    end
  end

  describe ".current" do
    it "returns the current edition" do
      expect(described_class.current.id).to eq("iala-2023")
    end
  end

  describe ".predecessor" do
    it "returns the prior edition" do
      e2023 = described_class.find("iala-2023")
      expect(described_class.predecessor(e2023).id).to eq("iala-2022")
    end

    it "returns nil for the oldest edition" do
      oldest = described_class::LINEAGE.first
      expect(described_class.predecessor(oldest)).to be_nil
    end
  end

  describe ".successor" do
    it "returns the next edition" do
      e1970 = described_class::LINEAGE.first
      expect(described_class.successor(e1970).id).to eq("iala-2009")
    end

    it "returns nil for the newest edition" do
      newest = described_class::LINEAGE.last
      expect(described_class.successor(newest)).to be_nil
    end
  end

  describe ".pairs" do
    it "yields 8 (predecessor, current) pairs for 9 editions" do
      pairs = described_class.pairs.to_a
      expect(pairs.length).to eq(8)
    end

    it "yields pairs in lineage order" do
      first_pair = described_class.pairs.first
      expect(first_pair.map(&:id)).to eq(["iala-1970-89", "iala-2009"])
    end
  end
end