# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Ports the IALA Dictionary (MediaWiki at `https://www.iala.int/wiki/dictionary/`) to a Glossarist Concept Browser site deployed on GitHub Pages at `https://www.glossarist.org/iala-vocab/`. The deployment pattern follows `oimlsmart/vocab`.

Nine cumulative-edition datasets live under `datasets/`, forming a lineage from `iala-1970-89` through `iala-2023` (current). Each dataset is complete upon itself — the cumulative state of the dictionary at that year.

Cross-edition relationships are encoded as a directed `supersedes` chain (newer → immediate predecessor). The concept-browser derives `superseded_by` at render time from incoming edges. This matches the OIML/vocab convention; see "Edition series model" below.

## Architecture

`lib/iala_vocab/` is a typed library that owns the data pipeline. Parent namespace `module IalaVocab` is declared in `lib/iala_vocab.rb`; every public class is autoloaded from there (never use `require_relative` for code under `lib/`). `scripts/` are thin entry points that load the library via `bundle exec`.

The library uses `Glossarist::V3::*` model classes throughout for concept serialization.

### Public classes

| Class | Responsibility |
|---|---|
| `IalaVocab::Edition` | Immutable value object: id, year, urn, status, ref, description |
| `IalaVocab::EditionSeries` | Single source of truth for the lineage: `LINEAGE`, `current`, `predecessor`, `successor`, `pairs` |
| `IalaVocab::ConceptFile` | Multi-doc YAML stream read/write with dirty tracking via `Glossarist::V3::*` |
| `IalaVocab::CrossEditionLinker` | Builds the `supersedes` chain (newer → immediate predecessor only) |
| `IalaVocab::LifecycleMarker` | Within-edition (Superseded)/(Discontinued) lifecycle detection |
| `IalaVocab::CitationExtractor` | Parses `Quelle:`/`Referenz:`/`Reference:`/bare attribution into `sources[]` |
| `IalaVocab::GermanTranslator` | Appends `language_code: deu` localized docs across all editions |
| `IalaVocab::RegisterBuilder` | Emits `register.yaml` from `Edition` metadata + section tree |
| `IalaVocab::Auditor` | Per-concept, per-edition, and cross-edition invariant validation |
| `IalaVocab::ApiClient` | MediaWiki API client with on-disk caching |

### Forbidden patterns

- `Object#send` to call private methods
- `instance_variable_set` / `instance_variable_get`
- `respond_to?` for type checking
- `require_relative` for code under `lib/` (use autoload declared in the parent file)
- `double()` / `instance_double` in specs — real model instances only

## Edition series model

```
iala-1970-89 → iala-2009 → iala-2012 → iala-2015 → iala-2016
            → iala-2017 → iala-2018 → iala-2022 → iala-2023 (current)
```

Each edition is a separate dataset, complete upon itself. Cross-edition relationships use a **one-way `supersedes` chain** (newer → immediate predecessor only). The concept-browser derives `superseded_by` at render time from incoming edges — we do not store the inverse.

Within-edition lifecycle (`(Superseded)` and `(Discontinued)` MediaWiki page cases) is handled by `LifecycleMarker` and is orthogonal to the cross-edition chain.

### Adding a new edition

1. Append an `IalaVocab::Edition` to `IalaVocab::EditionSeries::LINEAGE` in `lib/iala_vocab/edition_series.rb` with `status: "current"`. Demote the prior current edition to `status: "superseded"`.
2. Place the dataset under `datasets/<id>/`.
3. Re-run the pipeline:
   ```bash
   bundle exec ruby scripts/transform_iala.rb <id>
   bundle exec ruby scripts/build_cumulative_editions.rb
   bundle exec ruby -e 'require "iala_vocab"; IalaVocab::CrossEditionLinker.new.run!'
   bundle exec ruby scripts/generate_register.rb
   bundle exec ruby scripts/audit_iala.rb
   ```
4. Update `site-config.yml`: prepend the new edition to `datasets:` and `datasetGroups[0].datasets`; set `datasetGroups[0].current` to the new id.
5. Run `bundle exec rspec`.

Adding an edition requires NO code changes to the linker, auditor, or register builder — they all read from `EditionSeries::LINEAGE` (OCP).

## Common commands

```bash
npm install                  # concept-browser + glossarist JS deps
bundle install               # ruby deps for scraper/transformer (httparty, nokogiri)

npm run generate             # reads site-config.yml → public/site-config.json + datasets.json
npm run dev                  # vite dev server at http://localhost:5173
npm run build                # produces dist/ for GH Pages

bundle exec ruby scripts/audit_iala.rb         # exit 0 = clean, exit 1 = schema errors
```

`npm run dev` runs `generate` first; `npm run build` does not. Always `npm run generate` after editing `site-config.yml` or any concept YAML.

The Vite config is loaded from `node_modules/@glossarist/concept-browser/vite.config.ts` with `NODE_PATH` pointed at the package's own `node_modules` — do not collapse these into a plain `vite` invocation.

## The data pipeline (run scripts in this order)

The scraper → transformer flow is two-phase with local caching. Re-runs are incremental: cached pages are skipped.

1. **`scrape_sections.rb`** — fetches `Chapter_Index` via MediaWiki CategoryTree, writes `reference-docs/scraped/sections/section-tree.json`. The 13 top-level sections (ids `0`–`12`) are hard-coded in `TOP_LEVEL_SECTIONS`; subsection ids (`1.1`, `1.2`, …) are discovered from the tree.
2. **`scrape_edition.rb "<Category_Name>"`** — fetches every category member's parsed HTML + raw wikitext + categories + langlinks, caches per-page JSON under `reference-docs/scraped/editions/<edition>/pages/`, and writes `index.json`. Category names map to edition ids via `EDITION_MAP`:
   - `IALA_Dictionary_1970-89_Edition` → `iala-1970-89`
   - `IALA_Dictionary_2023_Revision` → `iala-2023`
3. **`scrape_translations.rb`** — pulls French (`Classement_alphabétique` → `fra`), Spanish (`Indice_alfabeto_Español` → `spa`), and German (`German` → `deu`) category members into `reference-docs/scraped/translations/{fra,spa,deu}/`.
4. **`scrape_historic.rb`** — fetches `Category:Historic_Terms` members (pages with `(Superseded)` / `(Discontinued)` suffixes) into `reference-docs/scraped/editions/iala-historic/`. Used by `transform_historic.rb` for discontinued concepts; `(Superseded)` pages already live in their own edition category and are handled by `mark_superseded.rb`.
5. **`generate_register.rb`** — emits every edition's `register.yaml` via `IalaVocab::RegisterBuilder`. Combines the shared `section-tree.json` with edition-specific metadata from `IalaVocab::EditionSeries::LINEAGE`. Languages list is `eng, fra, spa, deu` (declared on every edition; concept-browser hides languages with zero localized docs).
6. **`transform_iala.rb <edition>`** — turns each cached page into a Glossarist v3 multi-doc YAML at `datasets/<edition>/concepts/<termid>.yaml`. See "Concept YAML schema" below.
7. **`IalaVocab::CrossEditionLinker.new.run!`** — for each `(predecessor, current)` pair in `EditionSeries.pairs`, matches concepts by `termid` and appends a one-way `supersedes` edge on `current` pointing at `predecessor`. The concept-browser derives `superseded_by` at render time from incoming edges. Idempotent: re-running on linked data touches zero files.
8. **`mark_superseded.rb`** — finds managed concepts whose `sources[].origin.link` URL ends in `_(Superseded)`, sets `status: superseded`, adds `dates: [{type: retired, ...}]` matching the target edition year, and writes a forward `supersedes` edge on the active target concept. Backward `superseded_by` is NOT stored — the concept-browser derives it from incoming edges.
9. **`inject_german.rb`** (or `IalaVocab::GermanTranslator.new.run!`) — reads `reference-docs/scraped/translations/deu/`, parses each German page via `IalaVocab::CitationExtractor` (extracts `Quelle:`/`Referenz:`/`Reference:`/bare attribution lines into structured `sources[]`), and appends a `<termid>-deu` localized doc to every matching concept across all 9 datasets. Idempotent.
10. **`transform_historic.rb`** — processes `(Discontinued)` pages cached by `scrape_historic.rb`. Each `<h2>` section becomes its own retired concept (status: retired, dates: accepted/retired), written into `datasets/iala-1970-89/concepts/<code>.yaml`. Writes a forward `retires` edge on the active target concept. Backward `retired_by` is NOT stored.
11. **`add_year_tags.rb`** — maps MediaWiki categories (e.g. `IALA Dictionary 2015 Revision`, `Approved by DWG`) to `dates[]` and `approval` on the managed concept.
12. **`download_images.rb`** — scrapes `src="…/images/…"` URLs out of cached page HTML, downloads to `public/images/iala/`, filters UI icons (`Geographylogo.png`, `Npx-` prefixed, <1KB). Writes `reference-docs/reports/image-map.json`.
13. **`audit_iala.rb`** (or `IalaVocab::Auditor.new.run!`) — validates per-concept (termid present/unique, `terms[]` non-empty, `definition[]` has content), per-edition (no duplicate termids), and cross-edition (every `supersedes` ref resolves to a real concept file in the target edition). Exits non-zero on errors — GH Pages build should fail closed on this.

## MediaWiki API client

`scripts/iala_api.rb` is the only network surface. Every request is cached by `MD5(canonical_url)` under `reference-docs/api-cache/<action>/<hash>.json`, where `<action>` is one of `parse`, `categorymembers`, `content`, or `misc` (derived from the MediaWiki API params). **Once cached, the cache is the source of truth — edits to upstream MediaWiki will not be picked up until you delete the cache file.** To force re-fetch, delete the relevant cached JSON (or all of `reference-docs/api-cache/`). The library exposes the same API via `IalaVocab::ApiClient` (preferred for new code).

- `RATE_LIMIT_DELAY` defaults to `0.2s` between requests; override with `IALA_API_DELAY=<seconds>`.
- Retries on server errors with exponential backoff (3 attempts). Client errors (4xx) raise immediately.
- `parse_page` returns `{ text:, categories:, langlinks: }`; `get_page_content` returns raw wikitext (used to recover the `'''N-N-NNN'''` numeric code that doesn't always survive HTML rendering).

## Concept YAML schema (Glossarist v3, multi-document)

Each file in `datasets/<edition>/concepts/` is a multi-doc YAML stream:

- **Doc 1 — managed concept**: `id`, `termid` (IALA numeric code like `4-4-400`, falls back to slugified title), `status: valid`, `domains[]` (points at `section-<n>` via the dataset URN), `sources[]` (authoritative ref to IALA Dictionary), optionally `related[]` (cross-edition), `dates[]`, `approval`.
- **Docs 2+ — localized concepts**: `id` = `<termid>-<lang>`, `language_code`, `terms[]` (`type: expression`, `designation`, `normative_status: preferred`), `definition[]` (`content`), optional `notes[]` (carries the "Please note that this is the term as it stands in the original IALA Dictionary edition" disclaimer from the MediaWiki `<i>` tags).

`transform_iala.rb` uses `LANG_MAP` (`español→spa`, `français→fra`, `deutsch→deu`) and walks `.LanguageLinks a` to emit one localized doc per language variant. The numeric code prefix is stripped from `definition` content; `.mw-parser-output p, ul, ol` is the definition body, with `catlinks`, `LanguageLinks`, `mw-lingo-tooltip`, and `#toc` removed.

Duplicate `termid`s are disambiguated with a `-N` suffix inside `transform_iala.rb`.

## Configuration & deployment

- **`site-config.yml`** — canonical config (id, basePath `/iala-vocab/`, branding, datasets, datasetGroups, features, pages). `npm run generate` turns this into `public/site-config.json` and `public/datasets.json`. Both are gitignored-visible artifacts.
- **`about-eng.md`** — markdown source for the About page, registered via `pages: [{type: about, source: about-eng.md}]` in `site-config.yml`. Becomes `public/pages/about.json` after `generate`.
- **`.github/workflows/build_deploy.yml`** — runs on push to `main`, on PR, on `workflow_dispatch`, and on `repository_dispatch: deploy` (this is how other repos can trigger a rebuild). Installs concept-browser from npm (NOT the `file:` reference in `package.json` — the workflow rewrites it), runs `npx concept-browser build`, uploads `dist/` as the Pages artifact, and deploys on `main`.
- **`basePath: /iala-vocab/`** — every URL is under this prefix because the site lives at `www.glossarist.org/iala-vocab/`, not a root domain. Image paths in `download_images.rb` (`/iala-vocab/images/iala/…`) and concept-browser routing assume this.

## Gitignored but load-bearing

`.gitignore` excludes these directories — they are not disposable:

- **`reference-docs/`** — cached MediaWiki API responses and pipeline outputs. Top-level layout:
  - `api-cache/{parse,content,categorymembers,misc}/<hash>.json` — raw HTTP cache keyed by `MD5(URL)`, subdir'd by MediaWiki action.
  - `scraped/editions/<edition>/{index.json,pages/}` — per-edition page envelopes produced by `scrape_edition.rb` and `scrape_historic.rb`.
  - `scraped/translations/{fra,spa,deu}/{index.json,*.json}` — translation page envelopes produced by `scrape_translations.rb`.
  - `scraped/sections/section-tree.json` — section tree produced by `scrape_sections.rb`.
  - `reports/image-map.json` — source-URL → local-path map from `download_images.rb`.
  - Required to re-run transform/link/audit without hitting the network. Treat as data provenance, not build output.
- **`dist/`** — `concept-browser build` output.
- **`.datasets/`** — concept-browser intermediate working dir.
- **`.omo/`** — planning docs (`plans/iala-vocab.md` is the original port plan with the full task breakdown).
- **`TODO.full/`** — task spec drafts (never committed; per-project convention).

If you need to regenerate `datasets/` from scratch, you must first populate `reference-docs/` by running the scraper — the transformer does not call the API.

## Known gotchas

- The README references `scripts/scrape_iala.rb`; that file does not exist. The actual entry points are `scrape_edition.rb`, `scrape_sections.rb`, and `scrape_translations.rb`.
- `transform_iala.rb` writes multi-doc YAML by concatenating `---` + `to_yaml` per doc — Ruby's `YAML.dump` already prepends `---`, so the manual prefix in the writer is belt-and-suspenders.
- Chapter 12 (Heritage) appears twice in the MediaWiki CategoryTree; `scrape_sections.rb` merges subsections by id and dedupes.
- Two datasets share the same `sections` tree (via `generate_register.rb`); a section change affects both editions.
- `scripts/historical/` contains one-shot migration scripts that have already run. Do not re-run them on current datasets — see `scripts/historical/README.md`.
