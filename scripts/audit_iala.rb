#!/usr/bin/env ruby
# Validates IALA dataset invariants. Thin wrapper around
# IalaVocab::Auditor. Exits 0 on clean, 1 on any error.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "iala_vocab"

ok = IalaVocab::Auditor.new.run!
exit(ok ? 0 : 1)