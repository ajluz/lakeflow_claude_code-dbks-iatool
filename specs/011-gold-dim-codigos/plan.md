# Implementation Plan: Gold Junk Dimension of Sale Codes

**Branch**: `011-gold-dim-codigos` | **Date**: 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/011-gold-dim-codigos/spec.md`

## Summary

Create `workspace.gold.dim_codigos`, the junk dimension of sale codes: one row per
combination of origin, access location, payment method and discount found among the
silver, plus members `-1` and `-2`. Every possible combination is included, not only those
some sale has (owner, during planning): 62 rows on 2026-11-05.

Technical approach, from [research.md](research.md): one materialized view in the
pipeline, `src/pipeline/03_gold/03_dim_codigos.sql`. It builds four small lists, the
distinct values of each code (origin and payment method and discount from `tb_venda`,
access location from `tb_acesso` plus `Desconhecido`), crosses them with `CROSS JOIN`,
sets `local_acesso` to `Não se aplica` for `ARQUIVO`, takes the `DISTINCT` result,
computes `sk_codigos = xxhash64(<4 codes>) & 9223372036854775807`, and adds the two
members with `UNION ALL`. The lists are crossed, never the tables. The key is derived from
the codes, so recomputing the view or adding a new value never changes an existing key.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines
(`CREATE OR REFRESH MATERIALIZED VIEW`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI

**Storage**: reads `workspace.silver.tb_venda` and `workspace.silver.tb_acesso` (batch);
writes `workspace.gold.dim_codigos`

**Testing**: dry run, one update, [quickstart.md](quickstart.md) queries, a second update
compared by checksum. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode. The
pipeline's glob `.../src/pipeline/**` covers the new file

**Project Type**: data pipeline

**Performance Goals**: the view is recomputed on each update (research, Decision 6): one
`DISTINCT` scan per value list (about 420,000 sales, 2.5 million accesses), then a cross
join of 2 × 4 × 3 × 4 values producing 60 rows

**Constraints**:
- Principle VII: a key that never changes; identity is not supported on materialized
  views, and the owner chose a deterministic key (spec, Clarifications);
- no full refresh needed or requested;
- Free Edition quota: about 4 minutes between updates.

**Scale/Scope**: 1 SQL file; no flows; no expectations; 4 documentation files updated; 62 rows.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads silver only (`tb_venda`, `tb_acesso`). No boundary view: silver carries no bronze lineage column. `quality = gold`. Built in the pipeline, not a script (the data is not static). |
| II. SQL-Only Declarative Pipelines | Yes | PASS | One `.sql` file, `CREATE OR REFRESH MATERIALIZED VIEW`; no imperative statement; no legacy syntax. |
| III. Data Quality Expectations on Request | Yes | PASS | None requested (FR-010). Checks by query. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a sale. The cross product includes `Desconhecido` as a location, so sales without an access row have a combination. |
| V. Dataset Types and Flows | Yes | PASS | Full-scan gold result → materialized view, read without `STREAM`. No flow, so no flow view. No `PARTITIONED BY`, no `CLUSTER BY`. File `03_dim_codigos.sql`, next number in `03_gold/`. |
| VI. Record Source and Hash Keys | No | n/a | Silver only. `origem_usuario` carries silver's `origem` unchanged. |
| VII. Kimball Dimensional Modeling | Yes | **DEVIATION** | Junk dimension named `dim_codigos`, as the principle requires. Single-column `sk_codigos`, deterministic, never reassigned (Decision 2). SCD type 1. Members `-1` / `-2`. Grain: one combination. References no dimension. Business key is the four codes, not a silver hash key: see Complexity Tracking. |
| Constraints | Yes | PASS | Three-level names; `dim_`, `sk_`, `origem_`, `data_carga`; `--profile` explicit; no AI Functions. |
| Workflow: target graph | Yes | PASS | `G3 dim_codigos`, fed by `S4 tb_venda` and `S2 tb_acesso`: exactly this design (values from both, crossed). |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines`: `materialized-view-sql.md` (identity unsupported; non-deterministic `SELECT` forces recompute), `sql-basics.md`. |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: no expectations. 3: no source changed. 4: n/a (no silver change). 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | PASS | None. `dim_codigos` does not exist today, so nothing is dropped. |

**Gate result (pre-research)**: PASS, one deviation justified below.
**Gate result (post-design, 2026-11-05)**: PASS. The design changed one spec wording,
`data_carga` (research, Decision 6), and no row above.
**Gate result (revision, 2026-11-05, cross join)**: PASS. The cross join is over value
lists, so the earlier known issue (crossing the tables) does not return.

## Project Structure

### Documentation (this feature)

```text
specs/011-gold-dim-codigos/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── gold-dim-codigos.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
src/pipeline/03_gold/
├── 01_vw_gold_dim_usuario_tb_usuario.sql   # unchanged
├── 02_dim_usuario.sql                      # unchanged
└── 03_dim_codigos.sql                      # NEW: materialized view

doc/
├── pipeline-reference.md   # CHANGED: ### dim_codigos as built
├── architecture.md         # CHANGED: features table (identity row no longer cites dim_codigos)
├── README.md               # CHANGED: layout and gold dataset count
└── known-issues.md         # CHANGED: cross-join item removed; identity item no longer names dim_codigos
```

`fato_venda`'s section in `doc/pipeline-reference.md` still describes the earlier
pipeline; its `sk_codigos` row is updated to point to the matching rule here.

**Structure Decision**: one dataset per file (Principle V); the pipeline glob already
covers it.

## Design Notes for Implementation

- **Header comment in Portuguese**: grain (every possible combination), SCD type 1, the
  value lists and why they are crossed instead of the tables, the four code rules, how the key is computed and why it is not an identity, the members, and how a
  fact resolves `sk_codigos`.
- **Query shape**: four CTEs, one per value list (`origens`, `locais`, `formas`,
  `descontos`) → `CROSS JOIN` of the four → `CASE` for the `ARQUIVO` location →
  `SELECT DISTINCT` → key computed over the final codes → `UNION ALL` of the two member
  rows → `current_timestamp() AS data_carga` on every row. Column order of FR-002.
- **Upload** the new file to the pipeline's workspace folder before the dry run, and
  confirm the workspace copy matches the repository.
- **Quota**: about 4 minutes between the two updates.

## Complexity Tracking

| Deviation | Why it is needed | Simpler alternative rejected |
|---|---|---|
| Principle VII: the business key is the four codes, not a silver hash key | A junk dimension describes a combination of codes; no silver entity or `_uuid` exists for it, and facts find the row by its codes | Adding a `codigos_uuid` (`md5` of the codes): a second key for the same thing that no table carries |
