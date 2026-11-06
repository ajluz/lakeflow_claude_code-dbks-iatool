# Implementation Plan: Gold Sales Fact

**Branch**: `013-gold-fato-venda` | **Date**: 2026-11-05, revised the same day | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/013-gold-fato-venda/spec.md`

## Revision (2026-11-05)

The first plan made the fact a materialized view. The owner adopted the Databricks
dimensional-modeling guidance, and the constitution was amended to v3.0.0: facts are
streaming tables fed from silver, with stream-static lookups (Principle V).

This plan replaces the dataset type and adds the "keys are resolved once" statement that
the amendment requires (research, Decisions 1 and 9). The lookups themselves are unchanged
(Decisions 2–6).

## Summary

Create `workspace.gold.fato_venda`, the sales fact.
- **Grain**: one row per sale of `silver.tb_venda`, 420,472 on 2026-11-05.
- **Columns**: the four dimension keys (`sk_tempo`, `sk_codigos`, `sk_curso`, `sk_usuario`)
  and two additive measures (`valor_desconto`, `valor_pago`).

Technical approach, from [research.md](research.md): one streaming table,
`src/pipeline/03_gold/07_fato_venda.sql`, defined as
`CREATE OR REFRESH STREAMING TABLE ... AS SELECT ... FROM STREAM(workspace.silver.tb_venda)`.

1. **CTE `vendas`**:
   - reads the sales stream;
   - computes the four sale codes with `dim_codigos`'s rules, including the requested rule
     that `ARQUIVO` gives the location `Não se aplica`;
   - looks up the location of site sales only, in `tb_acesso`.
2. **Dimension lookups**: each dimension is read without `STREAM` (a stream-static join) and
   joined with a `LEFT JOIN`, with the stream on the left. Each key is `coalesce(…, -1)`, so
   no sale can be dropped.
3. **Course lookup**: picks the version in effect at the sale, or the course's first version
   when the sale is older (owner). It is not limited to `__END_AT IS NULL`.
4. **When keys are set**: once, when a sale is processed. Each update loads the
   dimensions before the fact.

These `LEFT JOIN`s are load-time lookups. Queries from the fact to the dimensions use inner
joins, which are safe because every key exists.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines
(`CREATE OR REFRESH STREAMING TABLE ... AS`, `STREAM(...)`).

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI.

**Storage**:
- reads `STREAM(silver.tb_venda)` incrementally; `tb_venda` is append-only, the target of
  two append flows;
- reads as static snapshots: `silver.tb_acesso`, `gold.dim_tempo` (outside the pipeline),
  `gold.dim_codigos`, `gold.dim_curso` and `gold.dim_usuario`;
- writes `workspace.gold.fato_venda`.

**Testing**: dry run, update, the [quickstart.md](quickstart.md) queries, and a second
update with no new sales. No test framework.

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode.

**Project Type**: data pipeline.

**Performance Goals**: the first update processes the 420,472 existing sales against the
static dimensions and accesses (2.5 million rows). Later updates process only new sales.

**Constraints**:
- no sale dropped (Principles I and VII);
- the grain is documented before the build (Principle VII);
- keys are resolved once, and this plan states it (Principle V);
- no expectations;
- no full refresh;
- the generator is not run;
- about 4 minutes between updates.

**Scale/Scope**: 1 SQL file, no separate flows, 6 columns, 420,472 rows; 4 documentation
files.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v3.0.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads silver and gold only. `dim_tempo` is the static reference table that Principle I allows. Reconciliation: no join removes a sale; unmatched lookups go to `-1`; no exclusion. `quality = gold`. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | One `.sql` file, `CREATE OR REFRESH STREAMING TABLE ... AS`; no imperative statement; no legacy syntax. |
| III. Data Quality Expectations on Request | Yes | PASS | None requested (FR-011). |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a sale. |
| V. Dataset Types and Flows | Yes | PASS | **Facts are streaming tables**: fed by `STREAM(workspace.silver.tb_venda)`, an append-only source (append flows only). Lookups are stream-static: dimensions and `tb_acesso` are read without `STREAM`, each joined with a `LEFT JOIN` with the stream on the left and the key coalesced to `-1`. No inner join. The keys-resolved-once statement is in this plan (Summary, point 4) and in research Decision 9. File `07_fato_venda.sql`. No `PARTITIONED BY`. |
| VI. Record Source and Hash Keys | No | n/a | Silver only. The fact joins on silver's hash keys and on `curso_uuid`. |
| VII. Kimball Dimensional Modeling | Yes | PASS | `fato_` prefix. Grain stated in `doc/pipeline-reference.md` before the build. Only surrogate keys and measures; both measures additive. No null keys, with members `-1`. The date goes through `dim_tempo`. Codes go through the junk dimension. For SCD type 2, the version in effect is resolved, with the documented first-version fallback; not current-only. |
| Constraints | Yes | PASS | Three-level names; `--profile` explicit; no AI Functions. |
| Workflow: target graph | Yes | PASS | `G4 fato_venda`, fed by `S4 tb_venda`, `S2 tb_acesso`, `G0`–`G3`. |
| Workflow: skill consulted | Yes | PASS | `streaming-table-sql.md` (stream-static join: static side read as a snapshot at stream start), `scd-2-querying.md`; Databricks dimensional-modeling page. |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: none declared. 3: no source changed. 4: n/a. **5: documented grain, no null keys, row count = silver.** 6: documentation; `known-issues.md` loses "Sales missing from fato_venda". |
| Workflow: full refresh, table drop | Yes | PASS | None. `fato_venda` does not exist. Re-resolving keys later would need an approved full refresh, which is not planned. |

**Gate result (pre-research)**: PASS.

**Gate result (post-design, 2026-11-05)**: PASS. The Databricks page's natural-key fact
example is not followed, because the spec and Principle VII require surrogate keys
(research, Decision 1).

## Project Structure

### Documentation (this feature)

```text
specs/013-gold-fato-venda/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── gold-fato-venda.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks (regenerate for the streaming table)
```

### Source Code (repository root)

```text
src/pipeline/03_gold/
├── 01_ … 06_            # unchanged
└── 07_fato_venda.sql    # NEW: streaming table over STREAM(silver.tb_venda)

doc/
├── pipeline-reference.md   # CHANGED first: ### fato_venda (grain, keys, keys resolved once) before the build
├── known-issues.md         # CHANGED: "Sales missing from fato_venda" removed (fixed)
├── architecture.md         # CHANGED: features table (fact as a streaming table with stream-static lookups)
└── README.md               # CHANGED: layout and gold dataset count
```

**Structure Decision**: one dataset per file, the next number in the gold folder.

## Design Notes for Implementation

- **Header in Portuguese**, covering:
  - grain;
  - measures (both additive);
  - a streaming table over `STREAM(silver.tb_venda)`, each sale processed once;
  - stream-static lookups, `LEFT JOIN` with `-1`, and no inner join;
  - keys resolved once, after the same update's dimensions;
  - the `ARQUIVO` → `Não se aplica` rule;
  - the course rule.
- **Query shape**:
  1. CTE `vendas` over `STREAM(workspace.silver.tb_venda) AS v`, with a
     `LEFT JOIN workspace.silver.tb_acesso`.
  2. CTE `versoes_curso`, static over `dim_curso`: `sk_curso > 0`, plus
     `min(__START_AT) OVER (PARTITION BY curso_uuid)`.
  3. The final `SELECT` with four `LEFT JOIN`s and `coalesce(…, -1)`, columns in FR-002
     order.

  If the dry run rejects the CTE form over a stream, inline `vendas` as a subquery in
  `FROM`.
- **Order**: document the grain first, then upload, dry run and update.
- **Second update**: there are no new sales, so the stream reads 0 rows and nothing
  changes.

## Complexity Tracking

No deviation.
