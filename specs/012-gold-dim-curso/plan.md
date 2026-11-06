# Implementation Plan: Gold Course Dimension (SCD Type 2)

**Branch**: `012-gold-dim-curso` | **Date**: 2026-11-05, revised the same day | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-gold-dim-curso/spec.md`

## Revision (2026-11-05, during implementation)

The first design loaded the members with a one-time snapshot flow (research, Decision 5).
It is in production in part: update `3f2c2771` created `dim_curso` with its 3 course
versions. The platform then rejected the snapshot flow:
`MULTI_QUERY_SNAPSHOT_TARGET_NOT_SUPPORTED`, because a snapshot flow can share a target only
on SCD type 1.

The owner kept the single-table design and asked for the members to come from a view
before the dimension (spec, Clarifications). They now come from a members view through a
once-only `AUTO CDC` flow (research, Decision 9). Everything else in the first design
stands. Decision 10 records the fallback.

## Summary

`workspace.gold.dim_curso` is the course dimension with history (SCD type 2):
- one row per version of a course, plus members `-1` and `-2`;
- columns `sk_curso`, `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso DECIMAL(9,2)`,
  `data_carga`, `__START_AT` and `__END_AT`;
- 5 rows on 2026-11-05.

It is one streaming table with two flows, each reading its own view:

| View | Flow |
|---|---|
| `vw_gold_dim_curso_dados_database` (exists): reads `STREAM(vw_bronze_tb_curso)` and computes `sk_curso = xxhash64(curso_uuid, timestamp_change) & 9223372036854775807` | `gold_dim_curso_flow`, an `AUTO CDC ... STORED AS SCD TYPE 2` with the same key, sequence and delete condition as `tb_curso` (in production) |
| `vw_gold_dim_curso_membros` (new): the two member rows in the same shape, with change time `1900-01-01` | `gold_dim_curso_membros_flow`, an `AUTO CDC ONCE ...` with the same keys, sequence, delete condition, columns and SCD type. It runs once and is idle afterwards |

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`,
`CREATE FLOW ... AS AUTO CDC [ONCE] INTO`).

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI.

**Storage**:
- reads `vw_bronze_tb_curso` as a stream, and the members view;
- writes `workspace.gold.dim_curso`.

**Testing**: dry runs, one update, the [quickstart.md](quickstart.md) queries, and a second
update compared by checksum. No test framework.

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode.

**Project Type**: data pipeline.

**Performance Goals**: incremental. The members flow runs once.

**Constraints**:
- one key per version, never reassigned (Principle VII);
- the same `KEYS`, `SEQUENCE BY` and delete condition as `tb_curso`;
- no full refresh and no drop;
- the generator's `update row` and `delete row` are not run;
- about 4 minutes between updates.

**Scale/Scope**:
- 1 new view file; `05_dim_curso.sql` renamed to `06_dim_curso.sql`;
- 2 flows, no expectations, 5 rows;
- the documentation updates listed under Project Structure.

**Open points**, settled by dry run in order (research, Decision 9):
1. a batch members view;
2. if that fails, a streaming members view;
3. if that fails too, stop and offer Decision 10.

None is marked NEEDS CLARIFICATION, because each has a defined next step.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads bronze only through `vw_bronze_tb_curso`, under the exception that names `gold.dim_curso`. Same `KEYS`, `SEQUENCE BY` and delete condition as `silver_tb_curso_flow`, in both flows. No cleansing or rule on the feed: the change view derives the key and leaves columns out. The members view reads no dataset (batch form) or uses the feed only as a trigger (streaming form). The bronze dependency is documented. `quality = gold`. Note A. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | `.sql` files, current syntax, flows only. |
| III. Data Quality Expectations on Request | Yes | PASS | None requested. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No feed row is dropped; a delete closes a version. |
| V. Dataset Types and Flows | Yes | PASS | A change feed in gold goes to a streaming table. Intermediate logic lives in temporary views, one per file, numbered before the target (`04_`, `05_`, then `06_dim_curso.sql`). Two `AUTO CDC` flows, not a `UNION` across streams. Explicit `KEYS`, the delete before `SEQUENCE BY`, SCD type 2. No `PARTITIONED BY`. |
| VI. Record Source and Hash Keys | No | n/a | Silver only. |
| VII. Kimball Dimensional Modeling | Yes | PASS | One key per version, deterministic. Business key `curso_uuid`. SCD type 2 through `AUTO CDC`. Members `-1` / `-2`, valid from 1900-01-01. The dimension references no other dimension. |
| Constraints | Yes | PASS | `vw_gold_dim_curso_membros` follows `vw_<zone>_<target>_<source>`: the source is the members literal, as with `dim_usuario`'s members. Flow `gold_dim_curso_membros_flow`. |
| Workflow: target graph | Yes | PASS | `G2 dim_curso` fed by the course feed. The two views are not drawn (Principle V exception). The graph edge `B3 → G2` is redrawn through `vw_bronze_tb_curso`. |
| Workflow: skill consulted | Yes | PASS | `auto-cdc-sql.md`; Databricks docs `ldp/cdc` (snapshot plus CDC needs SCD type 1) and `ldp/database-replication` (`AUTO CDC ONCE`). |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: no expectations. 3: no source changed. 4: n/a. 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | PASS | Neither is needed. The owner approved a full refresh for the rejected snapshot design; it was never run and is not reused. |

**Note A, record source**: `origem` is left out (owner). The constitution's sentence that
`tb_curso` and `dim_curso` "carry the same price type and record source" describes the
shared view; it is not a MUST. A PATCH rewording is suggested through
`/speckit-constitution`.

**Gate result (revision)**: PASS, no deviation.

## Project Structure

### Documentation (this feature)

```text
specs/012-gold-dim-curso/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/gold-dim-curso.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
src/pipeline/03_gold/
├── 01_ … 03_                                  # unchanged
├── 04_vw_gold_dim_curso_dados_database.sql    # exists (update 3f2c2771), unchanged
├── 05_vw_gold_dim_curso_membros.sql           # NEW: members view
└── 06_dim_curso.sql                           # RENAMED from 05_dim_curso.sql; adds the members flow

doc/
├── pipeline-reference.md   # dim_curso as built (bronze dependency); both views
├── architecture.md         # features table; graph edge
├── README.md               # layout; gold dataset count
└── known-issues.md         # identity item removed; SCD 2 snapshot limitation noted
```

**Structure Decision**: one dataset per file, flow views numbered before the target. The
rename keeps the folder sequential. `import-dir --overwrite` does not delete files, so the
workspace's `05_dim_curso.sql` is deleted by hand. Otherwise two files would define
`dim_curso`.

## Design Notes for Implementation

- **`05_vw_gold_dim_curso_membros.sql`**:
  - header in Portuguese: members for facts whose course is missing or does not apply;
    change time 1900-01-01, so they are valid for any date; read once by a flow that
    then stays idle;
  - columns in the order of the change view.
- **`06_dim_curso.sql`**:
  - the current file, renamed;
  - the snapshot comment is not reintroduced;
  - the members flow is added with the same clauses as the change flow plus `ONCE`;
  - its Portuguese comment explains `ONCE`.
- **Sequence of attempts**:
  1. batch form: dry run, then update;
  2. if the dry run rejects the batch source: streaming form, dry run, then update;
  3. if that fails too: revert to the course-only files, re-upload, and offer Decision 10.

  Never a full refresh.
- **Checks after the update**:
  - 5 rows; members open, at 1900-01-01;
  - the course rows' key checksum is still `-380130840`;
  - in the streaming form, exactly 1 row per member.
- **Second update**: all rows identical, `data_carga` included. The members flow is idle.

## Complexity Tracking

No deviation.
