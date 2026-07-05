# IALA Dictionary

[![Deploy](https://github.com/glossarist/iala-vocab/actions/workflows/build_deploy.yml/badge.svg)](https://github.com/glossarist/iala-vocab/actions/workflows/build_deploy.yml)

The IALA Dictionary is a comprehensive vocabulary of maritime aids-to-navigation terminology published by the International Association of Marine Aids to Navigation and Lighthouse Authorities (IALA). This repo deploys the dictionary as a [Glossarist Concept Browser](https://github.com/glossarist/concept-browser) site at **<https://www.glossarist.org/iala-vocab/>**.

The deployment pattern follows [`oimlsmart/vocab`](https://github.com/oimlsmart/vocab).

## Editions

Nine cumulative-edition datasets live under `datasets/`, forming a lineage:

```
iala-1970-89 → iala-2009 → iala-2012 → iala-2015 → iala-2016
            → iala-2017 → iala-2018 → iala-2022 → iala-2023 (current)
```

Each edition is complete upon itself — the cumulative state of the dictionary at that year. Cross-edition relationships use a directed `supersedes` chain (newer → immediate predecessor); the concept-browser derives the inverse at render time.

## Repository structure

```
datasets/                # 9 edition datasets (authoritative, hand-curated)
  iala-<year>/
    concepts/*.yaml      # Glossarist v3 multi-doc YAML per concept
    register.yaml        # per-edition metadata (id, year, urn, status, description)
lib/iala_vocab/          # typed Ruby library (autoloaded, model-driven)
scripts/                 # pipeline entry points (thin wrappers around lib/)
scripts/historical/      # one-shot migration scripts (provenance only — do not re-run)
reference-docs/          # cached MediaWiki API responses + scraped envelopes (gitignored)
site-config.yml          # deployment config (datasets, branding, basePath)
iala_vocab.gemspec       # path-gem spec — referenced from Gemfile
```

See [`CLAUDE.md`](./CLAUDE.md) for the full architecture: `Edition` / `EditionSeries` / `ConceptFile` / `CrossEditionLinker` / `LifecycleMarker` / `CitationExtractor` / `GermanTranslator` / `RegisterBuilder` / `Auditor` / `ApiClient`.

## Building locally

### Prerequisites

- Node.js 20+ and npm
- Ruby 3.0+ and Bundler

### Install

```bash
npm install                       # concept-browser + glossarist JS deps
bundle install                    # Ruby deps (glossarist gem, httparty, nokogiri, rspec)
```

### Generate and dev

```bash
npm run generate                  # reads site-config.yml → public/site-config.json + datasets.json
npm run dev                       # vite dev server at http://localhost:5173
```

`npm run dev` runs `generate` first; `npm run build` does not — always run `generate` after editing `site-config.yml` or any concept YAML.

### Production build

```bash
npm run build                     # produces dist/ for GH Pages
```

### Test

```bash
bundle exec rspec                 # spec suite for lib/iala_vocab/ (real models, no doubles)
bundle exec ruby scripts/audit_iala.rb   # exit 0 = clean, exit 1 = schema/URI errors
```

## Updating the dataset

Datasets are authoritative — hand-curated by editors. To regenerate from upstream MediaWiki:

1. Populate `reference-docs/` via the scrape scripts (see CLAUDE.md "Data pipeline"):
   ```bash
   bundle exec ruby scripts/scrape_sections.rb
   bundle exec ruby scripts/scrape_edition.rb "IALA_Dictionary_2023_Revision"
   bundle exec ruby scripts/scrape_translations.rb
   bundle exec ruby scripts/scrape_historic.rb
   ```
2. Transform cached pages into Glossarist v3 YAML:
   ```bash
   bundle exec ruby scripts/transform_iala.rb iala-2023
   bundle exec ruby scripts/build_cumulative_editions.rb
   bundle exec ruby -e 'require "iala_vocab"; IalaVocab::CrossEditionLinker.new.run!'
   bundle exec ruby scripts/generate_register.rb
   bundle exec ruby scripts/audit_iala.rb
   ```

For adding a new edition, see "Adding a new edition" in [`CLAUDE.md`](./CLAUDE.md) — it's a one-line append to `IalaVocab::EditionSeries::LINEAGE` plus dataset placement; no code changes anywhere else (OCP).

## License

CC BY 4.0. See [`LICENSE`](./LICENSE) for details.