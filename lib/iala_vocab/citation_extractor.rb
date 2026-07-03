# frozen_string_literal: true

module IalaVocab
  # Extracts bibliographic citations (Reference:, Quelle:, Referenz:,
  # and bare attribution lines like "C.I.E. (Auszug)") from rendered
  # MediaWiki HTML and returns them as structured source entries.
  #
  # Used by language-specific translators (GermanTranslator today;
  # English uses a richer extractor inside transform_iala.rb that
  # handles more annotation types — Note:, Symbol:, Unit:, etc.).
  class CitationExtractor
    CITATION_PREFIX_RE = %r{
      \A\s*
      (?:<br\s*/?>[\s\n]*)*
      (?:Quelle|Referenz|Reference)\s*:\s*
    }ix.freeze

    BARE_CITATION_RE = %r{
      \A\s*
      ((?:C\.I\.E\.|I\.E\.C\.|ISO)(?:\s*\(.+\))?)
      \s*\z
    }ix.freeze

    MODIFIED_RE = /\((?:abgewandelt|angepasst|modified|adapted)\)/i.freeze

    attr_reader :paragraphs, :sources

    def initialize(html)
      @paragraphs = extract_paragraphs(html)
      @sources = []
      partition!
    end

    private

    def extract_paragraphs(html)
      doc = Nokogiri::HTML(html)
      doc.css(".LanguageLinks").each(&:remove)
      doc.css(".mw-lingo-tooltip").each(&:remove)
      doc.css("#toc").each(&:remove)
      doc.css("i").each { |n| n.remove if n.text.include?("Please note") }

      parser_output = doc.css(".mw-parser-output").first || doc
      big = parser_output.at_css("big big big")
      designation = big ? big.text.strip : nil

      parser_output.css("p, ul, ol").reject do |el|
        el.inner_html.include?("editsection") ||
          el.text.strip.empty? ||
          el.text.strip.match?(/\A\d+-\d+-\d+\z/) ||
          (big && el.text.strip == designation)
      end.map { |el| el.text.strip }
    end

    def partition!
      @paragraphs = @paragraphs.reject do |text|
        if (stripped = text.sub(CITATION_PREFIX_RE, "")) && stripped != text
          add_source(stripped)
          next true
        end
        if (m = text.match(BARE_CITATION_RE))
          add_source(m[1])
          next true
        end
        false
      end
    end

    def add_source(text)
      @sources << {
        ref_text: text.strip,
        modified: !!(text =~ MODIFIED_RE),
      }
    end
  end
end