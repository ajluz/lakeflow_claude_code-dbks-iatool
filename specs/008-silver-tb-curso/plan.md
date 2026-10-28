# Implementation Plan: Silver Course Catalog as the Latest Version of Each Course

**Branch**: `008-silver-tb-curso` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-silver-tb-curso/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Build `workspace.silver.tb_curso` as an SCD type 1 table over the course catalog's change
feed: one row per `curso_uuid` with the latest name, level and price, updates overwritten
in place, deletions applied, changes ordered by `timestamp_change`. The table carries
`origem = 'DATABASE'` and `data_carga`, and none of the change-control or lineage columns.

Technical approach, from [research.md](research.md): two SQL files under
`src/pipeline/02_silver/`, matching the diagram's `V5` and `S5`.
- **`12_vw_bronze_tb_curso.sql`**: the boundary view over `workspace.bronze.dados_database`.
  It excludes `source_file_name` and `_rescued_data` and, because an `AUTO CDC` flow can
  only read a named view, it also converts `valor_curso` to `DECIMAL(9,2)` and adds
  `origem` and `data_carga`.
- **`13_tb_curso.sql`**: the target with three warn expectations, and one `AUTO CDC` flow
  `silver_tb_curso_flow`: `KEYS (curso_uuid)`, `APPLY AS DELETE WHEN change_type = 'delete'`,
  `SEQUENCE BY timestamp_change`, `COLUMNS * EXCEPT (change_type, timestamp_change,
  processing_time)`, `STORED AS SCD TYPE 1`.

**Constitution v1.11.0** (2026-10-28) allows this view: Principle I's exception "the
course feed's boundary view" names `vw_bronze_tb_curso` and lets it convert the price and
add `origem` and `data_carga`. The plan was first checked against v1.10.0, with two
deviations that the amendment now covers.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`,
`CREATE FLOW ... AS AUTO CDC INTO ... STORED AS SCD TYPE 1`, `CONSTRAINT ... EXPECT`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless), one `AUTO
CDC` flow; Unity Catalog; Databricks CLI v1.11.0

**Storage**:
- reads `workspace.bronze.dados_database` (feature 003);
- writes `workspace.silver.tb_curso`.

**Testing**: dry run, then [quickstart.md](quickstart.md) against the three inserts. The
update and the deletion are proven at the talk (spec, Clarifications 2026-10-28). No test
framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: three change rows today; any update applies only new changes

**Constraints**:
- `FROM STREAM(...)` of `AUTO CDC` accepts only a table or view name, never a query
  (skill `auto-cdc-sql.md`);
- the delete condition goes before `SEQUENCE BY` (Principle V; the parser requires it);
- implementation MUST NOT run the generator's `update row` or `delete row`;
- no refresh of existing tables: `tb_curso` is new;
- Free Edition quota: about 4 minutes between updates; the warehouse is never stopped
  while queries still run on it.

**Scale/Scope**:
- 2 SQL files: 1 view and 1 table with 1 flow;
- 3 expectations;
- 4 documentation updates;
- 3 rows expected now; 3 after the talk's update; 2 after its deletion.

Nothing is marked NEEDS CLARIFICATION. Facts of 2026-10-28 (research): the source holds
three `insert` rows sharing one `timestamp_change`, `valor_curso` is `double`, and each
`curso_uuid` equals `md5(nome_curso)`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.11.0 (first checked against v1.10.0; see Complexity Tracking).

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | The bronze read goes through `vw_bronze_tb_curso`, which excludes `source_file_name` and `_rescued_data`, converts the price and adds `origem` and `data_carga`, and does nothing else: exactly the v1.11.0 exception "the course feed's boundary view". `tb_curso` carries `quality = silver` and no lineage column. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Two `.sql` files in current syntax: `AUTO CDC INTO`, not `APPLY CHANGES`. |
| III. Data Quality Through Expectations | Yes | PASS | Three named warn expectations on `tb_curso`, null handling explicit. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rejection rule. A deletion is the source's own change: the change row stays in bronze, and the gold dimension keeps history. Nothing is discarded by a rule. |
| V. Dataset Types and Flows | Yes | PASS | Silver is streaming: a view over `STREAM(...)` and a streaming table. Change feed applied with `AUTO CDC INTO`, explicit `KEYS (curso_uuid)`, `SEQUENCE BY timestamp_change`, delete condition before `SEQUENCE BY`. **The target is SCD type 1.** The flow-view rule covers append flows; this is not one. No layout clause. Files `12_` and `13_`. |
| VI. Record Source and Hash Keys | Yes | PASS | `tb_curso` exception: no hash key, the source identifier is the `KEYS` column. `origem` is the literal `'DATABASE'` (the request's `'DABATASE'` is a typo, spec Assumptions); `data_carga` is set. Sales and accesses produce `md5` of the course name, equal to the source identifier (verified in feature 007). |
| VII. Kimball Dimensional Modeling | No | N/A | No gold dataset. The future `dim_curso` reads the same view, with the same key, sequence and delete condition. |
| Constraints | Yes | PASS | Naming: `vw_bronze_tb_curso` is the named exception to the boundary-view rule (v1.11.0). Everything else passes: three-level names in `workspace`, flow `silver_tb_curso_flow`, `--profile databricks-free`, no AI Functions. |
| Workflow: target graph | Yes | PASS | The diagram shows `B3 → V5 (vw_bronze_tb_curso) → S5 (tb_curso)`. The two datasets are exactly `V5` and `S5`. |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines`: `auto-cdc-sql.md` (source must be a named view; delete before `SEQUENCE BY`; `COLUMNS * EXCEPT`; SCD type 1 default), `streaming-table-sql.md`, `expectations-sql.md`. |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: three expectations in the data quality tab. 3: rows = distinct courses whose latest change is not a deletion. 4: `origem` populated; the hash-key gate is exempt (Principle VI). 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | PASS | New datasets only. |

**Gate result (pre-research, v1.10.0)**: PASS with two deviations, both from one owner
decision (the diagram's view name), justified in Complexity Tracking.

**Gate result (post-design, v1.11.0)**: PASS, no deviations. The amendment of 2026-10-28
covers both.

## Project Structure

### Documentation (this feature)

```text
specs/008-silver-tb-curso/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── silver-tb-curso.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    └── 02_silver/
        ├── 01_ … 11_                    # unchanged (features 004–007)
        ├── 12_vw_bronze_tb_curso.sql    # NEW: course feed view (boundary + origem, data_carga, price)
        └── 13_tb_curso.sql              # NEW: target, 3 expectations, AUTO CDC SCD type 1 flow

doc/
├── pipeline-reference.md   # CHANGED: tb_curso and vw_bronze_tb_curso as built
├── architecture.md         # CHANGED: features row for AUTO CDC SCD type 1 points to 13_tb_curso.sql
├── README.md               # CHANGED: layout lists 12_–13_, dataset count
└── known-issues.md         # CHANGED: "tb_curso is not consumed by any gold table" restated
```

**Structure Decision**: the two files continue `02_silver/` in reading order. The
pipeline's glob covers them, so its settings do not change.

## Design Notes for Implementation

- **The view is the only place to shape the feed.** `SELECT * EXCEPT (source_file_name,
  _rescued_data, valor_curso)`, then `CAST(valor_curso AS DECIMAL(9,2)) AS valor_curso`,
  `'DATABASE' AS origem`, `current_timestamp() AS data_carga`. No filter.
- **The flow drops the control columns.** `COLUMNS * EXCEPT (change_type,
  timestamp_change, processing_time)`; they stay available to `SEQUENCE BY` and the
  delete condition.
- **The target is declared before its flow**, with only its three constraints, as
  `tb_usuario`'s first design was (accepted by the dry run in feature 006).
- **Header comments in Portuguese.** They state SCD type 1, the key, the sequence and the
  delete condition, why the view adds three columns, and that updates and deletions are
  shown at the talk.
- **Quota**: one upload, one dry run, one update, then the no-new-data update.
- **The talk**: the quickstart's last section is the owner's script for the update and the
  deletion.

## Complexity Tracking

No violations to justify under constitution v1.11.0.

History: checked against v1.10.0, the design had two deviations from Principle I and the
naming rule: the view's name `vw_bronze_tb_curso`, and its three added columns. The owner
chose the diagram's name and asked for an amendment (spec, Clarifications 2026-10-28). The
alternative rejected was a pure boundary view plus a shaping view: a dataset the diagram
does not draw, and a `double` price in gold. Constitution v1.11.0 adopted the exception on
2026-10-28.
