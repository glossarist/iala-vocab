# frozen_string_literal: true

module IalaVocab
  # One-shot content cleanup for known transform/translation-ingestion
  # defects, applied uniformly across all editions in the series:
  #
  # - *Term recovery*: localized docs whose only designation is a numeric
  #   code (+2-3-120+, +3-1 -030+) or a leaked MediaWiki translation-subpage
  #   suffix (+Oil Lamp/es+) get the real term recovered from the first
  #   line of the definition body, which is then removed from it.
  # - *Code-line strip*: definition bodies that still open with a numeric
  #   code line (including the space-typo variants +3-1 -030+) lose it.
  # - *Echo strip*: definition bodies that open by repeating one of the
  #   doc's own designations lose that line.
  # - *Suffix fallback*: designations still carrying +/es+, +/fr+, +/de+
  #   (when no recoverable first line exists) have the suffix stripped.
  # - *Dedup*: when a file carries multiple localized docs for the same
  #   language, the best one is kept (clean designation preferred, then
  #   definition presence).
  # - *Deletion*: MediaWiki test/translation-twin concepts are removed
  #   (+testpage-de+ everywhere; +audible-signal-es+ and +fog-signal-es+
  #   where present) and dangling +related+ edges to them are dropped.
  #
  # Idempotent: re-running on clean data touches zero files.
  class ContentCleaner
    NUMERIC_CODE = /\A\d{1,2}-\d{1,2}(?:\s?-?\s?\d{1,3})?\z/
    LANG_SUFFIX = %r{/(es|fr|de)\z}
    TERM_LIKE_MAX = 80
    DELETED_TERMIDS = %w[testpage-de audible-signal-es fog-signal-es].freeze

    attr_reader :stats

    def initialize(series: EditionSeries, dry_run: false)
      @series = series
      @dry_run = dry_run
      @stats = Hash.new(0)
      @unresolved = []
    end

    def run!
      deleted = {}
      @series.all.each do |edition|
        deleted[edition.id] = delete_junk(edition)
        clean_edition(edition)
      end
      scrub_dangling_edges(deleted.values.flatten)
      print_report
      @unresolved.empty?
    end

    private

    def delete_junk(edition)
      deleted = DELETED_TERMIDS.filter_map do |termid|
        path = File.join(edition.concepts_dir, "#{termid}.yaml")
        next unless File.exist?(path)

        File.delete(path) unless @dry_run
        stats[:concepts_deleted] += 1
        puts "deleted #{edition.id}/#{termid}"
        termid
      end
      deleted
    end

    def clean_edition(edition)
      Dir.glob(File.join(edition.concepts_dir, "*.yaml")).each do |path|
        cf = ConceptFile.read(path)
        next unless cf.managed

        cf.localized.each { |lc| clean_localized(path, lc) }
        dedupe_languages(path, cf)
        next unless cf.dirty?

        cf.save! unless @dry_run
        stats[:files_rewritten] += 1
      end
    end

    def clean_localized(path, lc)
      data = lc.data
      return unless data

      recover_designation(path, data)
      strip_leading_artifacts(data)
    end

    def recover_designation(path, data)
      terms = data.terms.to_a
      return unless terms.size == 1

      designation = terms.first.designation.to_s
      return unless bad_designation?(designation)

      content = data.definition.to_a.first&.content.to_s
      first, rest = split_first_line(content)
      if term_like?(first)
        terms.first.designation = first
        data.definition.first.content = rest if data.definition.to_a.any?
        stats[:terms_recovered] += 1
      elsif designation.match?(LANG_SUFFIX)
        terms.first.designation = designation.sub(LANG_SUFFIX, "")
        stats[:suffixes_stripped] += 1
      else
        @unresolved << "#{path}: numeric designation #{designation.inspect} with no recoverable term"
      end
    end

    def strip_leading_artifacts(data)
      definition = data.definition.to_a
      return unless definition.any?

      content = definition.first.content.to_s
      original = content
      loop do
        first, rest = split_first_line(content)
        break if first.nil?

        if first.match?(NUMERIC_CODE)
          stats[:code_lines_stripped] += 1
          content = rest
        elsif data.terms.to_a.any? { |t| t.designation.to_s == first }
          stats[:echo_lines_stripped] += 1
          content = rest
        else
          break
        end
      end
      definition.first.content = content if content != original
    end

    def dedupe_languages(path, cf)
      groups = cf.localized.group_by { |lc| lc.data&.language_code }
      keep = []
      changed = false
      groups.each_value do |docs|
        best = docs.max_by { |lc| doc_score(lc) }
        keep << best
        changed = true if docs.size > 1
      end
      return unless changed

      order = cf.localized.map { |lc| lc.data&.language_code }
      keep.sort_by! { |lc| order.index(lc.data&.language_code) || 0 }
      stats[:duplicate_docs_removed] += cf.localized.size - keep.size
      dropped = (cf.localized - keep).map { |lc| "#{path} [#{lc.data&.language_code}]" }
      puts "deduped #{dropped.join(", ")}"
      cf.localized.replace(keep)
    end

    def doc_score(lc)
      data = lc.data
      designation = data&.terms.to_a.first&.designation.to_s
      score = 0
      score += 2 unless bad_designation?(designation)
      score += 1 if data&.definition.to_a.any? { |d| d.content.to_s.match?(/\S/) }
      score
    end

    def bad_designation?(designation)
      designation.match?(NUMERIC_CODE) || designation.match?(LANG_SUFFIX)
    end

    def split_first_line(content)
      return [nil, ""] if content.nil? || content.empty?

      lines = content.lines
      first = lines.first.to_s.strip
      rest = lines.drop(1).join.sub(/\A\s*\n/, "")
      [first, rest]
    end

    def term_like?(line)
      return false if line.nil? || line.empty?

      line.length <= TERM_LIKE_MAX &&
        !line.match?(NUMERIC_CODE) &&
        !line.match?(/[.;:]\z/)
    end

    def scrub_dangling_edges(deleted_ids)
      return if deleted_ids.empty?

      @series.all.each do |edition|
        Dir.glob(File.join(edition.concepts_dir, "*.yaml")).each do |path|
          cf = ConceptFile.read(path)
          next unless cf.managed&.related&.any? { |r| deleted_ids.include?(r.ref&.id) }

          cf.managed.related.replace(
            cf.managed.related.reject { |r| deleted_ids.include?(r.ref&.id) }
          )
          cf.save! unless @dry_run
          stats[:edges_scrubbed] += 1
          puts "scrubbed dangling edge in #{path}"
        end
      end
    end

    def print_report
      puts @dry_run ? "Dry run:" : "Cleanup:"
      stats.each { |action, count| puts "  #{action}: #{count}" }
      unless @unresolved.empty?
        puts "  UNRESOLVED (manual review needed):"
        @unresolved.each { |u| puts "    #{u}" }
      end
    end
  end
end
