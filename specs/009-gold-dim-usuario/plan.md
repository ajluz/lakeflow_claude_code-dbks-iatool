# Implementation Plan: Gold User Dimension

**Branch**: `009-gold-dim-usuario` | **Date**: 2026-10-28, revised 2026-11-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-gold-dim-usuario/spec.md`

**Note**: Revised on 2026-11-04 by the owner's direction to rebuild the dimension with
`AUTO CDC` (tasks.md, Phase 9). It replaces the materialized view of the first version.

## Summary

Build `workspace.gold.dim_usuario`, the first gold dataset: one row per silver user plus
an "unknown" and a "not applicable" member, SCD type 1, with a surrogate key that can
never be reassigned.

Technical approach, from [research.md](research.md): a temporary view reads
`STREAM(workspace.silver.tb_usuario)`, computes
`sk_usuario = xxhash64(usuario_uuid) & 9223372036854775807`, and makes each silver row emit
the user and the two members, with fixed keys `-1` and `-2`. An `AUTO CDC` flow applies it
to a streaming table, keyed on `usuario_uuid` and sequenced by silver's `data_carga`, which
reduces the repeated members to one row each. The dimension declares no expectations.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE OR REFRESH STREAMING TABLE`, `CREATE TEMPORARY VIEW`, `CREATE FLOW ... AS AUTO CDC
INTO`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI

**Storage**:
- reads `workspace.silver.tb_usuario` (feature 006), streaming;
- writes `workspace.gold.dim_usuario`.

**Testing**: dry run, then [quickstart.md](quickstart.md), including a stability check
across two updates. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode. The
pipeline's source glob is `.../src/pipeline/**`, so `03_gold/` needs no settings change

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: 941,236 rows on the first load, from about 2.8 million rows the view
emits (three per silver row); later updates process only new silver rows

**Constraints**:
- Principle V: a gold dataset fed by a change feed is a streaming table;
- Principle VII: a single-column surrogate key that keeps its value across updates; a
  mechanism that can reassign keys MUST NOT be used;
- identity columns are not supported on `AUTO CDC` targets;
- changing the existing materialized view to a streaming table requires dropping it, with
  the owner's explicit approval;
- Free Edition quota: about 4 minutes between updates.

**Scale/Scope**: 2 SQL files in `03_gold/`; 1 flow; no expectations; 4 documentation
updates; 941,234 + 2 = 941,236 rows.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads silver only (`tb_usuario`). No boundary view: silver tables carry no bronze lineage column (research, Decision 6). `quality = gold`. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Two `.sql` files in the pipeline, with no imperative statement. |
| III. Data Quality Expectations on Request | Yes | PASS | The spec requests no expectation, so none is declared (FR-008). Keys are verified by query after a load. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a row. The dimension does not re-apply silver's rules. |
| V. Dataset Types and Flows | Yes | **DEVIATION** | Streaming table with `AUTO CDC`, SCD type 1 declared. No delete condition: see Complexity Tracking. No layout clause, and no `UNION` of a stream. Files `01_vw_gold_dim_usuario_tb_usuario.sql` and `02_dim_usuario.sql`. |
| VI. Record Source and Hash Keys | Yes | PASS | `usuario_uuid` is carried unchanged; `origem` is carried from silver. |
| VII. Kimball Dimensional Modeling | Yes | PASS | Denormalized, references no dimension. Surrogate key `sk_usuario`, single column, deterministic from the business key, so it cannot change on refresh (Decision 2). Business key `usuario_uuid` retained. **SCD type 1** declared. "Unknown" (`-1`) and "not applicable" (`-2`) members. Grain: one user. |
| Constraints | Yes | PASS | Three-level name; `dim_` prefix; `sk_`, `_uuid`, `origem`, `data_carga`; flow named `gold_dim_usuario_tb_usuario_flow`; `--profile databricks-free`; no AI Functions. |
| Workflow: target graph | Yes | **DEVIATION** | The diagram shows `S3 (tb_usuario) → G1 (dim_usuario)`, without the flow view: see Complexity Tracking. |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines`: `auto-cdc-sql.md`, `streaming-table-sql.md`. The Databricks `AUTO CDC` and limitations pages, for snapshot flows and identity columns. |
| Workflow: completion gates | Yes | DONE | 1: dry run and update. 2: no expectation declared, so nothing to show. 3: rows = silver users + 2. 4: n/a (no silver change). 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | DONE | The owner approved dropping the earlier materialized view (T025). No full refresh was run. |

**Gate result (post-design, 2026-11-04)**: PASS, with the two deviations recorded below.

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
        ├── 01_vw_gold_dim_usuario_tb_usuario.sql   # NEW: flow view, computes the key
        └── 02_dim_usuario.sql                      # NEW: streaming table, 1 flow

doc/
├── pipeline-reference.md   # CHANGED: ### dim_usuario as built; intro
├── architecture.md         # CHANGED: features table
├── README.md               # CHANGED: layout and dataset count
└── known-issues.md         # CHANGED: identity-key item
```

`src/pipeline/03_gold/01_dim_usuario.sql`, the first version's materialized view, is
removed from the repository and from the workspace.

**Structure Decision**: Principle V places a flow view in its own file, numbered just
before the target's file. The pipeline's glob already covers both.

## Design Notes for Implementation

- **Flow view**: computes `sk_usuario` and the gold `data_carga`, and renames silver's
  `data_carga` to `data_carga_silver`, because a flow cannot compute columns and the
  sequence column must not reach the target. Each silver row emits three rows through
  `explode(array(named_struct(...), ...))`: the user and the two members, whose sequence is
  fixed at `TIMESTAMP'1900-01-01'` (research, Decision 8).
- **Users flow**: `KEYS (usuario_uuid)`, `SEQUENCE BY data_carga_silver`, `COLUMNS * EXCEPT
  (data_carga_silver)`, `STORED AS SCD TYPE 1`.
- **The target declares its columns** to fix the data model's column order.
- **Header comments in Portuguese**: grain, SCD type 1, how the key is computed and why it
  is not an identity column, the two members and their keys, and that facts resolve
  `sk_usuario` by joining on `usuario_uuid` and fall back to `-1`.
- **Quota**: one upload, one dry run, one update, then a second update for the stability
  check.

## Complexity Tracking

| Deviation | Why it is needed | Simpler alternative rejected |
|---|---|---|
| Principle V: no delete condition on the `AUTO CDC` flow | `silver.tb_usuario` is append-only and delivers no delete event, so no condition can be true | `APPLY AS DELETE WHEN false`: satisfies the wording and documents nothing |
| Workflow: a flow view the diagram does not draw | An `AUTO CDC` flow reads only a named source and cannot compute columns, and the key, the gold `data_carga` and the members must be produced somewhere | Computing the key in silver: it would change `silver.tb_usuario`, outside this feature's scope, and a surrogate key belongs to the dimension |
