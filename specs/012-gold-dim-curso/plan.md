# Implementation Plan: Gold Course Dimension (SCD Type 2)

**Branch**: `012-gold-dim-curso` | **Date**: 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-gold-dim-curso/spec.md`

## Summary

Create `workspace.gold.dim_curso`, the course dimension with history (SCD type 2). It
holds one row per version of a course, plus members `-1` and `-2`. The columns are:
`sk_curso`, `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso DECIMAL(9,2)`,
`data_carga`, `__START_AT` and `__END_AT`. On 2026-11-05 that is 5 rows.

Technical approach, from [research.md](research.md):

1. **Flow view** `vw_gold_dim_curso_dados_database`:
   - reads `STREAM(vw_bronze_tb_curso)`, the existing course feed view;
   - computes `sk_curso = xxhash64(curso_uuid, timestamp_change) & 9223372036854775807`,
     one key per version;
   - passes through the four attributes, `data_carga` and the two control columns. It
     drops `origem` and `processing_time`.
2. **Streaming table** `dim_curso`, with two flows:
   - `gold_dim_curso_flow`, an `AUTO CDC ... STORED AS SCD TYPE 2` with the same key,
     sequence and delete condition as `tb_curso`;
   - `gold_dim_curso_membros_flow`, a one-time snapshot flow that loads the members at
     version `1900-01-01`. It follows `dim_usuario`'s pattern.

Keys never change: a version's key comes from its course and its change time, and
`AUTO CDC` only sets `__END_AT` on a closed version.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`,
`CREATE FLOW ... AS AUTO CDC [ONCE] INTO`).

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI.

**Storage**:
- reads `vw_bronze_tb_curso`, the pipeline-wide temporary view over
  `workspace.bronze.dados_database`, as a stream;
- writes `workspace.gold.dim_curso`.

**Testing**: dry run, one update, the [quickstart.md](quickstart.md) queries, and a second
update compared by checksum. No test framework.

**Target Platform**:
- Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
  (`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode;
- the pipeline's glob `.../src/pipeline/**` covers the new files.

**Project Type**: data pipeline.

**Performance Goals**: incremental. Only new change events are read; 3 events exist today.

**Constraints**:
- Principle VII: one key per version, never reassigned. Identity is not supported on
  `AUTO CDC` targets.
- Principle I exception: same `KEYS`, `SEQUENCE BY` and delete condition as `tb_curso`,
  and no rules on the feed.
- The generator's `update row` and `delete row` are not run (spec, Assumptions).
- No full refresh is needed.
- Free Edition quota: about 4 minutes between updates.

**Scale/Scope**: 2 SQL files, 2 flows, no expectations, 5 rows. The documentation changes
are listed under Project Structure.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads bronze only through `vw_bronze_tb_curso`, under the exception that names `gold.dim_curso`. Same `KEYS (curso_uuid)`, `SEQUENCE BY timestamp_change` and `APPLY AS DELETE WHEN change_type = 'delete'` as `silver_tb_curso_flow`. No cleansing or rule: the flow view only derives the surrogate key and leaves columns out. The bronze dependency is stated in `doc/pipeline-reference.md` (planned). `quality = gold`. See Note A on the record source. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | `.sql` files; `CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`, `CREATE FLOW ... AS AUTO CDC [ONCE] INTO`; no legacy syntax; no imperative statement. |
| III. Data Quality Expectations on Request | Yes | PASS | None requested (FR-009). Keys are checked by query. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No row of the feed is dropped. A delete closes a version and removes nothing. |
| V. Dataset Types and Flows | Yes | PASS | The change feed in gold goes to a streaming table. The intermediate logic is a temporary view, named `vw_<zone>_<target>_<source>`, in its own file numbered before the target's, producing the target's columns plus the two control columns the flow consumes. `KEYS`, delete before `SEQUENCE BY`, and SCD type 2 are stated. Current-version queries filter `__END_AT IS NULL`. No `PARTITIONED BY`. Files are `04_` and `05_` in `03_gold/`. |
| VI. Record Source and Hash Keys | No | n/a | Applies to silver. The business key is the source identifier (the `tb_curso` exception). |
| VII. Kimball Dimensional Modeling | Yes | PASS | `sk_curso`: single column, one per version, deterministic, never reassigned (Decision 3). The business key `curso_uuid` is retained. SCD type 2 through `AUTO CDC ... STORED AS SCD TYPE 2`. Members `-1` / `-2`. The dimension references no other dimension. |
| Constraints | Yes | PASS | Three-level names; `dim_`, `vw_`, `sk_`, `_uuid`, `data_carga`; flows `gold_dim_curso_flow` and `gold_dim_curso_membros_flow`; `--profile` explicit; no AI Functions. |
| Workflow: target graph | Yes | PASS | `G2 dim_curso` is fed by `B3 dados_database`, which is this design. The flow view is not drawn, as Principle V's exception allows (listed here). The graph's edge `B3 → G2` in `doc/architecture.md` is redrawn through `vw_bronze_tb_curso`, which it already passes through. |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines` skill: `auto-cdc-sql.md` (SCD 2 columns, `TRACK HISTORY`, snapshot flows and versions) and `scd-2-querying.md`. |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: no expectations. 3: no source changed (bronze and `tb_curso` counts unchanged). 4: n/a (no silver change). 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | PASS | Neither is needed. `dim_curso` does not exist today. |

**Note A, record source.** Principle I's course feed exception reads: "`silver.tb_curso`
and `gold.dim_curso` both read the feed through this view, so their current versions carry
the same price type and record source." The owner left `origem` out of `dim_curso` (spec,
Clarifications).
- The sentence states a consequence of sharing the view. It is not a MUST, so leaving the
  column out does not violate it.
- The price type does match (`DECIMAL(9,2)`).
- The sentence is now inaccurate for the record source. A PATCH amendment that rewords it
  is suggested as a follow-up through `/speckit-constitution`. It does not block this
  feature.

**Gate result (pre-research)**: PASS, with Note A.

**Gate result (post-design, 2026-11-05)**: PASS. Research added the flow view
(Decision 2) and the snapshot members (Decision 5). Neither changes a row above.

## Project Structure

### Documentation (this feature)

```text
specs/012-gold-dim-curso/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── gold-dim-curso.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
src/pipeline/02_silver/
└── 12_vw_bronze_tb_curso.sql                  # unchanged (header already names dim_curso)

src/pipeline/03_gold/
├── 01_vw_gold_dim_usuario_tb_usuario.sql      # unchanged
├── 02_dim_usuario.sql                         # unchanged
├── 03_dim_codigos.sql                         # unchanged
├── 04_vw_gold_dim_curso_dados_database.sql    # NEW: flow view (sk_curso)
└── 05_dim_curso.sql                           # NEW: streaming table + 2 AUTO CDC flows

doc/
├── pipeline-reference.md   # CHANGED: ### dim_curso as built, with the bronze dependency
├── architecture.md         # CHANGED: features table rows (SCD 2, identity, deterministic key, members); graph edge
├── README.md               # CHANGED: layout and gold dataset count
└── known-issues.md         # CHANGED: identity item removed (dim_curso was the last one)
```

**Structure Decision**: one dataset per file, with the flow view numbered just before its
target (Principle V). The pipeline glob already covers both files.

## Design Notes for Implementation

- **Headers in Portuguese**, as in `dim_usuario`'s files.
  - The view's header covers: the key per version and why it includes the change time;
    why `origem` and `processing_time` are left out; that it applies no rule to the feed
    (Principle I exception).
  - The table's header covers: grain, SCD type 2, `__START_AT` / `__END_AT` and the
    current-version filter, the shared key, sequence and delete condition with
    `tb_curso`, why there is no `TRACK HISTORY` (Decision 4), the members, and how a fact
    resolves the version.
- **Flow view**: an explicit column list in the order of [data-model.md](data-model.md),
  then `change_type`, `timestamp_change`.
- **Members flow**:
  - copy `dim_usuario`'s snapshot flow, including its comment not to remove `WITH VERSION`;
  - change `KEYS (curso_uuid)` and `STORED AS SCD TYPE 2`;
  - write `CAST(NULL AS DECIMAL(9,2))` for the price;
  - the column order is that of the flow's output.
- **Stop condition**: if, after the first update, a course row is closed or missing, or a
  member is not open, stop and report to the owner. Do not refresh or drop anything
  (research, Decision 5, Risk).
- **Upload** both files before the dry run, and confirm each workspace copy matches the
  repository.
- **Quota**: about 4 minutes between the two updates.

## Complexity Tracking

No deviation. Note A, the inaccurate sentence about the record source, is recorded above
as a suggested wording amendment, not a violation.
