# frozen_string_literal: true

require "spec_helper"

RSpec.describe IalaVocab::CitationExtractor do
  def html_for(body)
    %(<div class="mw-parser-output"><p>#{body}</p></div>)
  end

  it "extracts 'Quelle:' prefix citations" do
    html = %(<div class="mw-parser-output"><p>Definition body.</p><p>Quelle: C.I.E. (abgewandelt)</p></div>)
    extractor = described_class.new(html)
    expect(extractor.sources).to include(ref_text: "C.I.E. (abgewandelt)", modified: true)
    expect(extractor.paragraphs).to eq(["Definition body."])
  end

  it "extracts 'Referenz:' prefix citations" do
    html = %(<div class="mw-parser-output"><p>Body.</p><p>Referenz: C.I.E. (angepasst)</p></div>)
    extractor = described_class.new(html)
    expect(extractor.sources.first[:ref_text]).to eq("C.I.E. (angepasst)")
    expect(extractor.sources.first[:modified]).to be(true)
  end

  it "extracts 'Reference:' (English) prefix" do
    html = %(<div class="mw-parser-output"><p>Body.</p><p>Reference: I.E.C. (modified)</p></div>)
    extractor = described_class.new(html)
    expect(extractor.sources.first[:ref_text]).to eq("I.E.C. (modified)")
  end

  it "extracts bare C.I.E. attribution lines" do
    html = %(<div class="mw-parser-output"><p>Def body.</p><p>C.I.E. (Auszug)</p></div>)
    extractor = described_class.new(html)
    expect(extractor.sources.first[:ref_text]).to eq("C.I.E. (Auszug)")
    expect(extractor.sources.first[:modified]).to be(false)
  end

  it "strips lingo tooltips and LanguageLinks" do
    html = %(<div class="mw-parser-output">
      <p>Def.</p>
      <div class="LanguageLinks">should be stripped</div>
      <div class="mw-lingo-tooltip">should be stripped</div>
    </div>)
    extractor = described_class.new(html)
    expect(extractor.paragraphs).to eq(["Def."])
  end

  it "returns no sources when no citation is present" do
    extractor = described_class.new(html_for("Just a definition."))
    expect(extractor.sources).to be_empty
  end
end