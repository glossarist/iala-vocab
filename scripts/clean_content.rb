#!/usr/bin/env ruby
# One-shot content cleanup for known transform defects. Thin wrapper
# around IalaVocab::ContentCleaner. Pass --dry-run to preview changes.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "iala_vocab"

dry_run = ARGV.delete("--dry-run")
ok = IalaVocab::ContentCleaner.new(dry_run: dry_run).run!
exit(ok ? 0 : 1)
