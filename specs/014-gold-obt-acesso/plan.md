# Implementation Plan: Gold Access One-Big-Table

**Branch**: `014-gold-obt-acesso` | **Date**: 2026-11-06 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/014-gold-obt-acesso/spec.md`

## Summary

Create `workspace.gold.obt_acesso`, a one-big-table for access-funnel analysis.
- **Grain**: one row per combination of `local_acesso`, `endereco_ip_acesso` and `data`
  (owner, 2026-11-06).
- **Columns**: the two access attributes, `data` and 13 calendar attributes from
  `dim_tempo`, and three additive counts: `qtde_acesso`, `qtde_usuario`, `qtde_vendidos`.
- **Expected size on 2026-11-06**: 2,516,058 rows, measured by running the planned query
  as a batch (research, Decision 6).

Technical approach, from [research.md](research.md): one materialized view,
`src/pipeline/03_gold/08_obt_acesso.sql`, recomputed from its sources on every update.
1. **CTE `vendas_por_acesso`**: site sales of `silver.tb_venda` counted per `acesso_uuid`,
   so that the join to the accesses never duplicates an access.
2. **CTE `acessos`**: `silver.tb_acesso` left-joined to `vendas_por_acesso`, grouped by
   location, address and access day, with the three counts.
3. **Final `SELECT`**: `LEFT JOIN gold.dim_tempo` on `data` for the 13 calendar
   attributes, so no access is lost to the calendar. Columns in the requested order.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines
(`CREATE OR REFRESH MATERIALIZED VIEW ... AS`).

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI v1.11.0.

**Storage**:
- reads `workspace.silver.tb_acesso` (2,516,192 rows) and `workspace.silver.tb_venda`
  (420,472), both datasets of the pipeline;
- reads `workspace.gold.dim_tempo` (3,654 rows), the static calendar outside the pipeline;
- writes `workspace.gold.obt_acesso`.

**Testing**: dry run, update, the [quickstart.md](quickstart.md) queries against the
sources, and a second update. No test framework.

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode. The
pipeline's glob (`src/pipeline/**`) picks up the new file without a settings change.

**Project Type**: data pipeline.

**Performance Goals**: each update aggregates 2.5 million accesses and 420,472 sales; the
batch run of the query took under a minute on the serverless warehouse.

**Constraints**:
- no access lost (FR-009);
- the grain is documented before the build (FR-013; constitution, Principle VII);
- no expectations (FR-012);
- no full refresh and no table drop: `obt_acesso` does not exist yet;
- the generator is not run;
- about 4 minutes between updates.

**Scale/Scope**: 1 SQL file, 19 columns, about 2.5 million rows; 4 documentation files.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v3.1.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads silver (`tb_acesso`, `tb_venda`) and gold (`dim_tempo`, the static reference table Principle I allows). No bronze read, so no boundary view is needed. No access is lost: both joins are left joins from the accesses. `quality = gold`. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | One `.sql` file, `CREATE OR REFRESH MATERIALIZED VIEW ... AS`; no imperative statement, no legacy syntax. |
| III. Data Quality Expectations on Request | Yes | PASS | None requested (FR-012); counts are verified by query. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a row. Accesses silver excluded (impossible address) are already absent from `tb_acesso`, as a documented exclusion of feature 005. |
| V. Dataset Types and Flows | Yes | PASS | A denormalized gold table built by joins and aggregation is a full-scan result, so it is a **materialized view** read without `STREAM`. Not a fact, so the fact streaming rule does not apply. No intermediate dataset: two CTEs inside the view. File `08_obt_acesso.sql`, next in the gold folder. No `PARTITIONED BY`. |
| VI. Record Source and Hash Keys | No | n/a | Gold. The view joins on silver's `acesso_uuid`. |
| VII. Kimball Dimensional Modeling | Yes | PASS | `obt_` prefix. Grain stated in the spec (FR-002) and in `doc/pipeline-reference.md` before the build. The measures are not defined only here: accesses live in `tb_acesso`, sales in `tb_venda` and `fato_venda`; this table only counts them. Calendar attributes come from the conformed `dim_tempo`, with its names. |
| Constraints | Yes | PASS | Three-level names; `--profile` explicit; no AI Functions. |
| Workflow: target graph | Yes | PASS | `G5 obt_acesso`, fed by `S2 tb_acesso`, `S4 tb_venda` and `G0 dim_tempo`, exactly the edges of `doc/architecture.md`. |
| Workflow: skill consulted | Yes | PASS | `materialized-view-sql.md` (syntax; aggregates; no non-deterministic function outside `WHERE`, so no `current_timestamp()` column), `sql-basics.md`. |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: none declared. 3: no source changed. 4: n/a. 5: not a fact; its counts reconcile with the sources (quickstart). 6: documentation; `known-issues.md` loses the "obt_acesso still the earlier pipeline's" entry. |
| Workflow: full refresh, table drop | Yes | PASS | None. `obt_acesso` does not exist. |

**Gate result (pre-research)**: PASS.

**Gate result (post-design, 2026-11-06)**: PASS. The batch run confirms that no access is
lost and that the counts reconcile (research, Decision 6).

## Project Structure

### Documentation (this feature)

```text
specs/014-gold-obt-acesso/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── gold-obt-acesso.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
src/pipeline/03_gold/
├── 01_ … 07_            # unchanged
└── 08_obt_acesso.sql    # NEW: materialized view over tb_acesso, tb_venda and dim_tempo

doc/
├── pipeline-reference.md   # CHANGED first: ### obt_acesso (grain, sources, counts) before the build
├── architecture.md         # CHANGED: the Materialized views row links 08_obt_acesso.sql
├── README.md               # CHANGED: layout lists 08_obt_acesso.sql; gold dataset count
└── known-issues.md         # CHANGED: the obt_acesso entry is removed (fixed)
```

**Structure Decision**: one dataset per file, the next number in the gold folder.

## Design Notes for Implementation

- **Header in Portuguese**, covering:
  - the grain (location, address, day) and that the counts are summed per combination;
  - the sources and why `fato_venda` is not used (no access identifier);
  - sales are counted per access first, so an access is never duplicated;
  - left joins from the accesses: no access is lost to the sales or the calendar lookup;
  - the measures stay defined in their own datasets; this table only counts them.
- **Query shape**: the three steps of the Summary; `qtde_*` as BIGINT;
  `coalesce(sum(v.qtde_vendas), 0)` for accesses with no sale.
- **Order**: document the grain first, then upload, dry run and update.
- **Second update**: no data changed, so the counts stay the same.

## Complexity Tracking

No deviation.
