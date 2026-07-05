# Historical one-shot scripts

These scripts performed one-time data migrations or shape changes. They have
already run. **Do not re-run them on the current datasets** — the datasets are
the authoritative source of truth after migration.

| Script | What it did | When |
|---|---|---|
| `migrate_api_cache.rb` | Reorganized flat `reference-docs/api-cache/*.json` into per-action subdirs (`parse/`, `content/`, `categorymembers/`, `misc/`) | Prior to PR #5 |
| `migrate_related_ref_keys.rb` | Renamed `related[].ref.concept_id` → `id` across all 24K concept YAMLs (Citation.ref shape per v3 schema) | PR #5 |
| `migrate_origin_ref_shape.rb` | Rewrote `sources[].origin.ref: "string"` → `{ source: "string" }` hash form across all 24K concept YAMLs | PR #5 |
| `migrate_localized_data_shape.rb` | Moved `terms`/`definition`/`notes`/`sources`/etc. from top-level into `data:` per v3 canonical localized concept shape | PR #5 |
| `migrate_equivalent_to_supersedes.rb` | Stripped the legacy `equivalent` mesh (~193K edges) and installed the directed `supersedes` chain (~22K edges) | PR #8 |
| `strip_backward_lifecycle_edges.rb` | Stripped `superseded_by` and `retired_by` edges (browser derives from incoming forward edges) | PR #9 |

If you find a real need to re-run one of these, treat the script as a spec —
understand its intent first, then write a fresh one-shot targeted at the
current state. These scripts reference data shapes that may no longer exist.

The active pipeline scripts live in `scripts/` (parent directory). See
`CLAUDE.md` "Data pipeline" section for the canonical run order.