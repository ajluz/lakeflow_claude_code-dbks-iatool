# Implementation Plan: Gold User Dimension

**Branch**: `009-gold-dim-usuario` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-gold-dim-usuario/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Build `workspace.gold.dim_usuario`, the first gold dataset: one row per silver user plus
an "unknown" and a "not applicable" member, SCD type 1, with a surrogate key that can
never be reassigned. The spec's three constitution-driven points (`data_carga` instead of
`dt_carga`, the two members, stable keys) are taken as accepted: the owner moved to
planning after they were presented on 2026-10-28.

Technical approach, from [research.md](research.md): one SQL file,
`src/pipeline/03_gold/01_dim_usuario.sql`, defining a **materialized view** that reads
`workspace.silver.tb_usuario` in batch, keeps the latest row per `usuario_uuid`, computes
`sk_usuario = xxhash64(usuario_uuid)`, and appends the two members with fixed keys `-1`
and `-2`. Two `FAIL UPDATE` expectations guard the keys.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE OR REFRESH MATERIALIZED VIEW`, `CONSTRAINT ... EXPECT ... ON VIOLATION FAIL UPDATE`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless); Unity
Catalog; Databricks CLI v1.11.0

**Storage**:
- reads `workspace.silver.tb_usuario` (feature 006), batch;
- writes `workspace.gold.dim_usuario`.

**Testing**: dry run, then [quickstart.md](quickstart.md), including a key-stability check
across two updates. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`. The pipeline's
source glob is `.../src/pipeline/**`, so `03_gold/` needs no settings change

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: 941,236 rows; the view is recomputed in full on each update
(`current_timestamp()` and the window prevent incremental refresh), which is small at this
volume

**Constraints**:
- Principle V: a gold full-scan result is a materialized view read without `STREAM`;
- Principle VII: a single-column surrogate key that keeps its value across updates; a
  mechanism that can reassign keys MUST NOT be used;
- no refresh of existing tables; `dim_usuario` is new;
- Free Edition quota: about 4 minutes between updates.

**Scale/Scope**: 1 SQL file (first file of `03_gold/`); 2 expectations; 4 documentation
updates; 941,234 + 2 = 941,236 rows on 2026-10-28.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.11.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads silver only (`tb_usuario`). No boundary view: silver tables carry no bronze lineage column, and the diagram draws `S3 → G1` directly (research, Decision 6). `quality = gold`. No fact yet, so reconciliation is through the members. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | One `.sql` file, `CREATE OR REFRESH MATERIALIZED VIEW`. |
| III. Data Quality Through Expectations | Yes | PASS | `check_sk_usuario` and `check_usuario_uuid` (`IS NOT NULL`) with `ON VIOLATION FAIL UPDATE`: the case Principle III reserves for a null key in a gold dimension. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a row. The dimension does not re-apply silver's rules. |
| V. Dataset Types and Flows | Yes | PASS | Gold full-scan result as a materialized view, batch read. `UNION ALL` combines the silver rows with two literal rows, not streaming sources. No layout clause. File `01_dim_usuario.sql` in `03_gold/`. |
| VI. Record Source and Hash Keys | Yes | PASS | `usuario_uuid` is carried unchanged; `origem` is carried from silver. |
| VII. Kimball Dimensional Modeling | Yes | PASS | Denormalized, references no dimension. Surrogate key `sk_usuario`, single column, `xxhash64` of the business key: deterministic, so it cannot change on refresh (Decision 2). Business key `usuario_uuid` retained. **SCD type 1** declared. "Unknown" (`-1`) and "not applicable" (`-2`) members. Grain: one user. |
| Constraints | Yes | PASS | Three-level name `workspace.gold.dim_usuario`; `dim_` prefix; `sk_`, `_uuid`, `origem`, `data_carga` (the request's `dt_carga` follows the constitution's name); `--profile databricks-free`; no AI Functions. New project-code folder `src/pipeline/03_gold/`, named here. |
| Workflow: target graph | Yes | PASS | The diagram shows `S3 (tb_usuario) → G1 (dim_usuario)`. |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines`: `materialized-view-sql.md` (batch read, expectations, no identity on recompute), `expectations-sql.md` (`FAIL UPDATE`). |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: two expectations in the data quality tab. 3: rows = silver users + 2. 4: n/a (no silver change). 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | PASS | New dataset only. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations.

## Project Structure

### Documentation (this feature)

```text
specs/009-gold-dim-usuario/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── gold-dim-usuario.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    ├── 01_bronze/ …                 # unchanged
    ├── 02_silver/ …                 # unchanged
    └── 03_gold/
        └── 01_dim_usuario.sql       # NEW: materialized view, 2 FAIL UPDATE expectations

doc/
├── pipeline-reference.md   # CHANGED: ### dim_usuario as built; intro
├── architecture.md         # CHANGED: features table (materialized view; deterministic surrogate key)
├── README.md               # CHANGED: layout adds 03_gold/, dataset count adds gold
└── known-issues.md         # CHANGED: identity-key item no longer applies to dim_usuario
```

**Structure Decision**: `src/pipeline/03_gold/` is the gold zone folder the constitution's
layout names; `01_dim_usuario.sql` is its first file, in the diagram's reading order
(`G1`). The pipeline's glob already covers it.

## Design Notes for Implementation

- **Silver rows**: `SELECT ... FROM workspace.silver.tb_usuario QUALIFY row_number() OVER
  (PARTITION BY usuario_uuid ORDER BY data_carga DESC) = 1`, so the dimension is SCD type 1
  even if silver ever delivers a key twice.
- **Members**: two literal rows joined by `UNION ALL`, with every column typed as in the
  data model (`CAST(NULL AS INT)` for the age).
- **The target declares its two constraints only**, no column list; the select list fixes
  the column order of the data model.
- **Header comment in Portuguese**: grain, SCD type 1, why the surrogate key is a hash of
  the business key, the two members and their keys, and that facts resolve `sk_usuario`
  by joining on `usuario_uuid` and fall back to `-1`.
- **Quota**: one upload, one dry run, one update, then a second update for the
  key-stability check.

## Complexity Tracking

No violations to justify.
