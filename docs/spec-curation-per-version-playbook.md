# Spec Curation — Per-Version Maintainer Playbook

> **Audience:** Maintainer adding a new Odoo major (e.g. Odoo 21.0 ships) or auditing the spec corpora.
>
> **Background:** The MCP server exposes 4 corpora — CoreSymbol, LintRule, CLICommand, CLIFlag — each populated by `index-core` from upstream Odoo source plus optional curated JSON in `src/indexer/spec_data/`.
>
> **Pain motivating this doc:** When Odoo 17.0 was deployed, the "pending curation" banner appeared on `lint_check` and `cli_help` even though most data was correctly indexed. Investigation revealed the banner is mostly a cosmetic false-positive driven by missing `_curate_status` metadata, with one genuine data gap (CLIFlag).

---

## What each corpus IS

### CoreSymbol
Top-level Odoo API entities: `odoo.fields.Char`, `odoo.api.depends`, `odoo.models.Model`, `odoo.exceptions.UserError`, etc. Each carries `qualified_name`, `kind` (`field_type`/`class`/`function`), `signature`, `status` (`stable`/`deprecated`), `file_path`, `line`, and lifecycle properties (`added_in`, `removed_in`, `deprecated_in`) computed by `diff_engine` after indexing.

**Source:** 8 allow-list files parsed at `parser_odoo_core.py:25-34`:
1. `odoo/tools/safe_eval.py`
2. `odoo/tools/query.py`
3. `odoo/tools/sql.py`
4. `odoo/fields.py`
5. `odoo/models.py`
6. `odoo/api.py`
7. `odoo/sql_db.py`
8. `odoo/exceptions.py`

Path resolution adapts per version (`parser_odoo_core.py:211-255`): v8/v9 use `openerp/` prefix; v19+ resolve `fields.py`/`models.py`/`api.py` to the `odoo/orm/` package directory.

### LintRule
One indexable lint rule across Python (pylint-odoo, ruff) and JS (ESLint-odoo). Shape:
```json
{"rule_id": "E8101", "kind": "pylint-odoo", "message": "...", "severity": "error", "file_pattern": "*.py"}
```

**Source (per `parser_lint_rules.py:183-245`):**
- **Code-extract phase** (runs only for v17+ via `_version_has_test_lint`):
  - `odoo/addons/test_lint/tests/_odoo_checker_*.py` — AST parse `msgs = {"E8xxx": (...)}` dict → pylint-odoo rules
  - `odoo/addons/test_lint/tests/eslintrc` — JSON `rules` → eslint-odoo rules
  - `ruff.toml` at repo root — TOML `[lint].select` → ruff-builtin rules
- **Static-merge phase** (always): adds entries from `spec_data/lint_rules_<version>.json` if present.

### CLICommand
One `odoo-bin` subcommand. Shape: `{name: "server", description: "Start the odoo server", file_path: "odoo/cli/server.py"}`.

**Source:** `parser_cli.py:67-83` AST-walks `odoo/cli/*.py` (skipping `__init__.py`, `command.py`, underscore-prefixed) for top-level `ClassDef` subclassing `Command`. Fully automated — no static fallback.

### CLIFlag
One `--flag` of `odoo-bin server`. Shape:
```json
{"flag_name": "--workers", "command_name": "server", "type": "int",
 "default": "0", "help": "...", "status": "stable",
 "replacement_flag_name": null, "env_name": "ODOO_WORKERS", "posix_only": false}
```

**Source (per `parser_cli.py:197-224`):**
- AST walk of `odoo/tools/config.py` for all `<X>.add_option(...)` / `<X>.add_argument(...)` calls.
- Merge with `spec_data/cli_flags_<version>.json` (dedup by `(flag_name, command_name)`).

---

## The "pending curation" banner — exact trigger

Both `_lint_check` (`server.py:1244-1254`) and `_cli_help` (`server.py:1365-1454`) emit the banner when:

```cypher
MATCH (sm:SpecMetadata {kind: $kind, odoo_version: $v})
RETURN sm.curate_status AS curate_status
```

returns `curate_status == "pending"` (strict equality).

**Important asymmetry:**
- No SpecMetadata node → `curate_status = None` → banner does NOT fire.
- SpecMetadata exists with `curate_status = "pending"` → banner fires.

`_read_spec_curate_status` (`pipeline.py:702-725`) reads `_curate_status` from `spec_data/<kind>_<version>.json`, defaulting to `"pending"` when the file is missing or unreadable. `index-core` then writes that value into SpecMetadata.

**Net result for v17+:** because no `lint_rules_17.0.json` or `cli_flags_17.0.json` exists, every `index-core --version 17.0` writes `curate_status="pending"` regardless of whether real data was extracted.

---

## Observed production state for v17.0 (verified via MCP, 2026-05-11)

| Corpus | Real data on Neo4j? | Banner fires? | Conclusion |
|---|---|---|---|
| CoreSymbol | ✅ Yes (`fields.Char`, `api.depends`, `models.Model` all return real signatures) | No (different code path) | Working correctly |
| LintRule | ✅ Yes (11/11 probed codes hit incl. E8101/W8101/PO001/OE001) | ⚠ Yes | **Cosmetic false-positive** — fix by creating stub JSON |
| CLICommand | ✅ Yes (5/5 commands hit with descriptions) | – | Working correctly |
| CLIFlag | ❌ **No** (0/8 probed flags hit incl. `--addons-path`, `--workers`, `--data-dir`) | ⚠ Yes | **Genuine data gap** — re-run `index-core` or investigate parser |

---

## Per-version maintainer playbook

Steps for any new Odoo major (e.g. `21.0`):

| # | Step | Type | Time |
|---|------|------|------|
| 1 | `python -m src.indexer index-core --source ~/git/odoo_21.0 --version 21.0` | ✅ AUTO | ~5 min |
| 2 | Verify CoreSymbol count vs previous version. Drop >20% in any `kind` ⇒ source tree refactor; update `_resolve_core_paths` (`parser_odoo_core.py:211-255`) + add regression test per ADR-0005. | 🛠 SEMI-AUTO | 15-30 min (only on refactor events) |
| 3 | Create `src/indexer/spec_data/lint_rules_21.0.json` with `{"_curate_status": "source-parsed", "rules": []}` to suppress the "pending" banner. Code-extract already wrote real LintRule nodes from `test_lint`. | 👤 MANUAL | 2 min |
| 4 | Create `src/indexer/spec_data/cli_flags_21.0.json` with `{"_curate_status": "source-parsed", "flags": []}`. | 👤 MANUAL | 2 min |
| 5 | (Optional) Add removed-flag metadata: read v21 release notes, for each removed flag add `{flag_name: "--old", status: "removed", replacement_flag_name: "--new"}` to `cli_flags_21.0.json`. | 👤 MANUAL | 30-60 min, occasional |
| 6 | `python -m src.indexer.seed_patterns` re-run only if new patterns added. | ✅ AUTO | ~30s |
| 7 | `make test` + `make test-integration` | ✅ AUTO | ~2 min |

**Net human time per new version (no refactor, no flag removals):** ~5 minutes (steps 3+4 stubs).

---

## Reducing the recurring burden

### Recommendation 1 — Add `"source-parsed"` as a distinct `curate_status`

Today the schema effectively has two values: `"pending"` (placeholder, banner fires) and anything-else (banner does NOT fire). Adding `"source-parsed"` as a named value gives 3 explicit tiers:

- `"pending"` — static placeholder; data is INCOMPLETE; banner SHOULD fire.
- `"source-parsed"` — code-extract ran; data is auto-derived from upstream source; banner should NOT fire (data exists, no human curation yet).
- `"curated"` (or `"done"`) — manually reviewed and enriched; banner should NOT fire.

**Cost:** zero code changes (banner check is strict equality `== "pending"`). Just author the `lint_rules_*.json` / `cli_flags_*.json` with the new status string. The investigation playbook above already prescribes this.

### Recommendation 2 — Auto-generate `lint_rules_*.json` from pylint-odoo

For v8.0-v16.0 (where Odoo doesn't bundle `test_lint`), and as a cross-check for v17+, a script can fetch the OCA `pylint-odoo` repo at the version-tagged release, AST-parse `pylint_odoo/checkers/*.py` (same `msgs = {...}` shape the existing parser already handles), and emit our JSON schema. Outline:

```bash
pip download pylint-odoo==17.0.*    # or git clone --branch v17.0.x
python scripts/extract_pylint_odoo_rules.py \
  --source ./pylint-odoo \
  --version 17.0 \
  --out src/indexer/spec_data/lint_rules_17.0.json
```

A ~50-line script. Reuses `_parse_pylint_odoo_source` from `parser_lint_rules.py`.

### Recommendation 3 — Diagnose CLIFlag empty production state

Likely causes (in priority order):
1. **Production `index-core` ran with wrong source root** — `odoo/tools/config.py` not at expected path. Check production indexer log for `wrote N CLIFlag nodes` line; if N=0, source path is the issue.
2. **AST shape mismatch** — Odoo 17 wraps `add_option` in a non-trivial pattern (e.g. via `_add_option_compat` helper or decorator). Run `parse_cli_flags` against a fresh `git clone --branch 17.0 https://github.com/odoo/odoo` locally to confirm.
3. **`config.py` moved or split** in v17 — unlikely (path has been stable v8-v20) but verify.

**Next step:** SSH to production, run `python -m src.indexer index-core --source <odoo_17_source> --version 17.0 --verbose 2>&1 | grep CLIFlag` and check the count.

### Recommendation 4 — CI guard for spec corpus completeness

Add a smoke test (or extend `tests/test_indexer_spec.py`) that runs `index-core` against a known-good v17 source fixture and asserts each corpus has a minimum count:
- CoreSymbol ≥ 500 (`fields`, `models`, `api`, etc.)
- LintRule ≥ 30 (pylint-odoo + ruff + eslint)
- CLICommand ≥ 8 (`server`, `shell`, `db`, `scaffold`, `cloc`, `deploy`, `populate`, `neutralize`)
- CLIFlag ≥ 100 (server has ~150 options)

A regression where any count drops to 0 fails CI immediately, catching path refactors or parser drift before deploy.

---

## Decision matrix for the operator

| You see this in production | Likely cause | Fix |
|---|---|---|
| `lint_check` returns "pending" banner + no rule body | Real data IS in Neo4j, but `_SpecMeta.curate_status='pending'`. Cosmetic only. | Create `spec_data/lint_rules_<ver>.json` with `"_curate_status": "source-parsed"`. Re-run `index-core`. |
| `lint_check` returns "pending" + body says "0 hits / no rule found" | LintRule corpus is empty for that version. | Check: `_version_has_test_lint(version)` returns True for v17+. If yes, ensure source-root includes `odoo/addons/test_lint`. If v ≤ 16, you need a curated JSON. |
| `cli_help --addons-path` returns "12 commands" tree instead of flag detail | CLIFlag corpus is empty. (Current v17 prod state.) | Re-run `index-core` against a source where `odoo/tools/config.py` exists. Verify parser walks `add_option`/`add_argument` calls. |
| `lookup_core_api fields.Char` returns "not found" | Allow-list path resolution failed for this version. | Check `_resolve_core_paths` — paths may have moved (e.g. v19 ORM split). |

---

## File reference (for future maintainer)

- Parsing: `src/indexer/parser_odoo_core.py`, `parser_lint_rules.py`, `parser_cli.py`
- Orchestration: `src/indexer/pipeline.py::index_core` (lines 728-810)
- Curate status reader: `pipeline.py::_read_spec_curate_status` (lines 702-725)
- Writer: `src/indexer/writer_neo4j.py::write_spec_metadata` (lines 692-708)
- Banner trigger: `src/mcp/server.py:1244-1254` (lint_check), `1365-1454` (cli_help)
- Static placeholders: `src/indexer/spec_data/{lint_rules,cli_flags}_<version>.json`
- Schema reference: `src/indexer/spec_data/lint_rules_99.0.json` + `cli_flags_99.0.json` (only entries with real shape)
- Plan: `docs/superpowers/plans/2026-05-08-milestone-4-5-spec-wow.md`
- ADRs: `docs/adr/0002-spec-schema-policy.md`, `docs/adr/0005-core-coverage-version-paths.md`
