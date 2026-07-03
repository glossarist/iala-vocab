# frozen_string_literal: true

require "glossarist"
require "json"
require "fileutils"
require "yaml"
require "nokogiri"
require "uri"

# Parent namespace for the IALA Vocabulary data pipeline.
# All public classes are autoloaded from this file — never use
# `require_relative` for code under `lib/iala_vocab/`.
module IalaVocab
  autoload :Edition,             "iala_vocab/edition"
  autoload :EditionSeries,       "iala_vocab/edition_series"
  autoload :ConceptFile,         "iala_vocab/concept_file"
  autoload :CrossEditionLinker,  "iala_vocab/cross_edition_linker"
  autoload :LifecycleMarker,     "iala_vocab/lifecycle_marker"
  autoload :CitationExtractor,   "iala_vocab/citation_extractor"
  autoload :GermanTranslator,    "iala_vocab/german_translator"
  autoload :RegisterBuilder,     "iala_vocab/register_builder"
  autoload :Auditor,             "iala_vocab/auditor"
  autoload :ApiClient,           "iala_vocab/api_client"
end