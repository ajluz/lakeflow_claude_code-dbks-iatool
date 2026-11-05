# Implementation Plan: Gold Calendar Dimension

**Branch**: `010-gold-dim-tempo` | **Date**: 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/010-gold-dim-tempo/spec.md`

## Summary

Create `workspace.gold.dim_tempo`, the calendar dimension: one row per day from 2021-01-01
to 2030-12-31 (owner, 2026-11-05) plus an "unknown" (`-1`) and a "not applicable" (`-2`)
member, 3,654 rows, with an identity surrogate key.

Technical approach, from [research.md](research.md): a single SQL script,
`explorations/setup/04_dim_tempo.sql`, run by hand outside the pipeline. It is one `BEGIN
… END` block that creates the table if it is missing, stops if any day is repeated, inserts
only the members and days that are not there yet, and ends with a summary row. Because
existing rows are never rewritten, the identity keys never change and a second run changes
nothing. The calendar cell of `explorations/functions.py` is removed.

## Technical Context

**Language/Version**: Databricks SQL with SQL scripting (`BEGIN … END`, `DECLARE`, `IF`,
`SIGNAL`), on a serverless SQL warehouse

**Primary Dependencies**: Unity Catalog; Delta identity columns; Databricks CLI
(`experimental aitools tools query`)

**Storage**: writes `workspace.gold.dim_tempo` (regular Delta table); reads nothing else.
The table does not exist in the workspace today (checked 2026-11-05)

**Testing**: [quickstart.md](quickstart.md): two runs compared by checksum, plus content
queries. No test framework

**Target Platform**: Databricks Free Edition, profile `databricks-free`, warehouse
`f796ffb64302b6ba`

**Project Type**: data pipeline; this feature adds auxiliary setup code only

**Performance Goals**: one run in well under a minute (3,654 rows)

**Constraints**:
- Principle I: static reference data loaded by an idempotent script, listed in
  `doc/pipeline-reference.md`;
- Principle VII: a surrogate key that keeps its value; the script MUST NOT rebuild the
  table;
- a table drop is the user's decision: the script never drops.

**Scale/Scope**: 1 new setup script; 1 cell removed from `functions.py`; 6 documentation
files updated; 3,654 rows.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold, `quality = gold`. Static reference data outside the pipeline, loaded by an idempotent script (Decision 3) and listed in `doc/pipeline-reference.md` (FR-011). Reads no other dataset. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | The script uses `INSERT`, which this principle forbids for building pipeline datasets; `dim_tempo` is not one. Principle I's static-reference exception names the calendar and requires a script. No Python; the Python cell in `functions.py` is removed. |
| III. Data Quality Expectations on Request | Yes | PASS | The spec requests no expectation (FR-010). Uniqueness checked by query. |
| IV. Quarantine, Never Silently Discard | No | n/a | No source records, no rules. |
| V. Dataset Types and Flows | No | n/a | Not a pipeline dataset. The setup-script `NN_` rule applies: `04_dim_tempo.sql`, next step. |
| VI. Record Source and Hash Keys in Silver | No | n/a | Silver only. |
| VII. Kimball Dimensional Modeling | Yes | **DEVIATION** | Single-column `sk_tempo`; identity keys never reassigned because rows are never rewritten (Decision 3, 5). SCD type 1 declared. Members `-1` / `-2`. Grain: one day. References no dimension. Business key is `data`, not a silver hash key: see Complexity Tracking. |
| Constraints | Yes | PASS | Three-level name; `dim_` prefix; `sk_`, `fl_`, `data_carga`; script in `explorations/setup/`; `--profile` always explicit; no AI Functions. |
| Workflow: target graph | Yes | PASS | `dim_tempo` is drawn (`G0`), as a table outside the pipeline. |
| Workflow: skill consulted | Yes | PASS | Not pipeline code, so `databricks-pipelines` does not apply. `databricks-dbsql`, `references/sql-scripting.md`: DDL and DML inside `BEGIN … END`. |
| Workflow: completion gates | Yes | PLANNED | 1: no pipeline change; pipeline left as is. 2: no expectations. 3–5: n/a (no source, no silver change, no fact). 6: documentation (FR-011). |
| Workflow: full refresh, table drop | Yes | PASS | None needed: the table is absent. The script stops instead of dropping (Decision 4). |

**Gate result (pre-research)**: PASS, one deviation justified below.
**Gate result (post-design, 2026-11-05)**: PASS; the design added nothing that changes a
row above.

## Project Structure

### Documentation (this feature)

```text
specs/010-gold-dim-tempo/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── gold-dim-tempo.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
explorations/
├── functions.py               # CHANGED: last cell (calendar) removed, lines 512–608
└── setup/
    └── 04_dim_tempo.sql       # NEW: creates and fills workspace.gold.dim_tempo

doc/
├── pipeline-reference.md      # CHANGED: ### dim_tempo: script, period, members, SCD type
├── data-generation.md         # CHANGED: ## dim_tempo section removed / pointed to the script
├── getting-started.md         # CHANGED: new step 04; functions.py no longer creates it
├── known-issues.md            # CHANGED: "dim_tempo is reloaded on every run" removed
├── README.md                  # CHANGED: layout and "created outside the pipeline" row
└── architecture.md            # CHANGED: dim_tempo note names the script
```

`src/pipeline/` is not touched.

**Structure Decision**: auxiliary code under `explorations/setup/`, numbered in run order
(Repository layout). `04` is free since feature 009 deleted its seed script.

## Design Notes for Implementation

- **Header comment in Portuguese**, like `02_landing_volume.sql`: what the script creates,
  that it can be run again safely and why, how to run it, and the repeated-days stop.
- **Table definition**: the owner's 16 columns verbatim, `COMMENT` on the table,
  `TBLPROPERTIES ("quality" = "gold")`.
- **Period** in two `DECLARE`d variables (`v_inicio`, `v_fim`), so extending it is a
  one-line change.
- **Order inside the block**: create → repeated-days check → members → days → summary.
- **Summary `SELECT`**: `linhas`, `dias`, `membros`, `primeiro_dia`, `ultimo_dia`,
  `dias_repetidos`.
- **Run it twice** during validation; stop the warehouse afterwards with `--no-wait`.

## Complexity Tracking

| Deviation | Why it is needed | Simpler alternative rejected |
|---|---|---|
| Principle VII: the business key is `data`, not a silver hash key | The calendar has no silver source and no `_uuid`; the date itself identifies the row, and facts join on it | Adding `md5(data)` as `tempo_uuid`: a hash of a date that no table carries and nothing would join on |
