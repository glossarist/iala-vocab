# frozen_string_literal: true

require "httparty"
require "digest"

module IalaVocab
  # MediaWiki API client for the IALA Dictionary. Caches every response
  # by MD5(canonical_url) under `reference-docs/api-cache/<action>/`.
  #
  # Network is the only side effect; everything is replayable from cache.
  class ApiClient
    API_BASE = "https://www.iala.int/wiki/dictionary/api.php".freeze
    RATE_LIMIT_DELAY = Float(ENV.fetch("IALA_API_DELAY", "0.2"))
    CACHE_ROOT = File.expand_path("../../reference-docs/api-cache", __dir__)

    # Returns array of {pageid, ns, title} for all pages in a category.
    # Handles cmcontinue pagination automatically.
    def self.category_members(category_name, limit: 500)
      members = []
      continue_token = nil

      loop do
        params = {
          action: "query", format: "json",
          list: "categorymembers",
          cmtitle: "Category:#{category_name}",
          cmlimit: limit,
        }
        params[:cmcontinue] = continue_token if continue_token

        result = request(params)
        members += result.dig("query", "categorymembers") || []
        continue_token = result.dig("continue", "cmcontinue")
        break unless continue_token
      end

      members
    end

    # Returns { text:, categories:, langlinks: } for a page title.
    def self.parse_page(title)
      result = request(
        action: "parse", format: "json",
        page: title, prop: "text|categories|langlinks",
      )
      parse_data = result["parse"] || {}
      {
        text: parse_data.dig("text", "*"),
        categories: parse_data["categories"] || [],
        langlinks: parse_data["langlinks"] || [],
      }
    end

    # Returns raw wikitext string for a page title.
    def self.page_content(title)
      result = request(
        action: "query", format: "json",
        prop: "revisions", rvprop: "content", titles: title,
      )
      pages = result.dig("query", "pages") || {}
      page = pages.values.first || {}
      revisions = page["revisions"] || []
      revision = revisions.first || {}
      revision["*"]
    end

    class << self
      private

      def request(params)
        url_str = "#{API_BASE}?#{URI.encode_www_form(params)}"
        cache_file = cache_path(params)

        if File.exist?(cache_file) && File.size(cache_file).positive?
          return JSON.parse(File.read(cache_file))
        end

        fetch_with_retries(url_str, cache_file)
      end

      def cache_path(params)
        url_str = "#{API_BASE}?#{URI.encode_www_form(params)}"
        hash = Digest::MD5.hexdigest(url_str)
        subdir = subdir_for_params(params)
        File.join(CACHE_ROOT, subdir, "#{hash}.json")
      end

      def subdir_for_params(params)
        case params[:action]
        when "parse" then "parse"
        when "query"
          if params[:list] == "categorymembers"
            "categorymembers"
          elsif params[:prop] == "revisions"
            "content"
          else
            "misc"
          end
        else
          "misc"
        end
      end

      def fetch_with_retries(url_str, cache_file)
        retries = 0
        max = 3
        begin
          response = HTTParty.get(url_str)
          if response.code.between?(500, 599)
            raise "Server error #{response.code}"
          elsif response.code.between?(400, 499)
            raise "Client error #{response.code}: #{response.body}"
          end

          sleep RATE_LIMIT_DELAY
          FileUtils.mkdir_p(File.dirname(cache_file))
          File.write(cache_file, response.body)
          JSON.parse(response.body)
        rescue => e
          retries += 1
          if retries <= max && !e.message.start_with?("Client error")
            sleep(2**(retries - 1))
            retry
          end
          raise
        end
      end
    end
  end
end