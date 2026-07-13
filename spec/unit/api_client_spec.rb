# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::ApiClient do
  describe ".category_members" do
    it "is defined as a class method" do
      expect(described_class).to respond_to(:category_members)
    end
  end

  describe ".parse_page" do
    it "is defined as a class method" do
      expect(described_class).to respond_to(:parse_page)
    end
  end

  describe ".page_content" do
    it "is defined as a class method" do
      expect(described_class).to respond_to(:page_content)
    end
  end

  describe "API_BASE" do
    it "points at the IALA MediaWiki API" do
      expect(described_class::API_BASE).to eq(
        "https://www.iala.int/wiki/dictionary/api.php",
      )
    end
  end

  describe "RATE_LIMIT_DELAY" do
    it "defaults to 0.2 seconds" do
      expect(described_class::RATE_LIMIT_DELAY).to eq(0.2)
    end
  end

  describe "CACHE_ROOT" do
    it "points at reference-docs/api-cache relative to lib/" do
      expect(described_class::CACHE_ROOT).to match(%r{reference-docs/api-cache$})
    end
  end
end