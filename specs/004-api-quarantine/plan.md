# Implementation Plan: Validation and Quarantine of API Events

**Branch**: `004-api-quarantine` | **Date**: 2026-10-18 (revised for constitution v1.6.0) | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-api-quarantine/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Classify every bronze API event once, at the bronze-to-silver boundary. Events that fail
a rule are kept, unchanged, in a quarantine table. The others stay available for the
conformed silver tables of later features.

Technical approach, from [research.md](research.md): three SQL files under
`src/pipeline/02_silver/`, numbered per zone as constitution v1.6.0 requires.

- `01_vw_bronze_dados_api.sql`: the boundary view. It reads
  `STREAM(workspace.bronze.dados_api)` and selects every column except the bronze-only
  `source_file_name` and `_rescued_data`.
- `03_temp_tb_validacao_api.sql`: a private streaming table, partitioned by the flag. It
  reads the view, declares the three rules of the request (null-safe) as warn-only
  expectations, and adds `regras_violadas` (the names of the failed rules), the flag
  `fl_registro_invalido` derived from it, `origem = 'API'` and `data_carga`.
- `04_tb_quarentena.sql`: a published streaming table holding the flagged rows, with a
  warn expectation that each one names a rule.

The bronze files are renamed `01_`–`03_` with no content change.

Validation compares the quarantine table and the event log metrics with counts computed
directly on bronze.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH [PRIVATE] STREAMING TABLE`, `STREAM(...)`,
`CONSTRAINT ... EXPECT`, `PARTITIONED BY`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless); Unity
Catalog; Databricks CLI v1.11.0; the pipeline event log (`event_log(...)`) for metrics

**Storage**: reads the streaming table `workspace.bronze.dados_api` through a temporary
view. Writes one private streaming table and one managed streaming table in
`workspace.silver`

**Testing**: pipeline dry run (`--validate-only`), then the queries of
[quickstart.md](quickstart.md). They compare quarantine contents and expectation metrics
with counts computed directly on bronze. No test framework

**Target Platform**: Databricks Free Edition workspace, the existing development pipeline
`lakeflow_dataslight_dev`

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: the first update validates every bronze API event in one triggered
run. An update with no new bronze rows writes 0 rows to both tables

**Constraints**:
- validation removes nothing, and the rules only measure;
- `source_file_name` and `_rescued_data` never reach silver;
- `PARTITIONED BY` only on the validation table (Complexity Tracking);
- no full refresh without the owner's approval;
- the CLI profile is always passed explicitly;
- Free Edition quota: stop the SQL warehouse and wait about 4 minutes between updates.

**Scale/Scope**: 3 new SQL files, 3 renamed bronze files, 1 view, 2 tables,
4 expectations, 3 documentation updates. The pipeline settings are unchanged, because
the source glob already covers `02_silver/`

Nothing is marked NEEDS CLARIFICATION. Facts confirmed at implementation on 2026-10-18:
- `payload.info_pagamento.valor` is `DOUBLE`;
- the private three-level name and the lateral alias are accepted;
- `CLUSTER BY` on the Boolean flag is rejected, which led to partitioning.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.6.0 (amended 2026-10-18; the first check was against
v1.5.0).

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Both tables are in `workspace.silver` and read forward only. Bronze is read only through the boundary view `vw_bronze_dados_api`, which excludes `source_file_name` and `_rescued_data` and does nothing else. Neither silver table carries those columns. Each table carries `TBLPROPERTIES ("quality" = "silver")`. Every dataset read is defined in the pipeline. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Three `.sql` files, declarative, in current syntax (`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH [PRIVATE] STREAMING TABLE`). No `LIVE`, no `APPLY CHANGES`, no `CREATE OR REPLACE`, no imperative statements. Execution order comes from dependencies; the `NN_` prefixes only order reading. |
| III. Data Quality Through Expectations | Yes | PASS | The three rules are named `CONSTRAINT ... EXPECT` clauses on the validation table, a persisted dataset (the view cannot carry constraints). The quarantine table declares `regra_violada_registrada`. Every action is warn, deliberately: rows must survive to be routed (Principle IV). Every condition states its `NULL` treatment and cannot return `NULL`. The quarantine `WHERE` is a routing filter; the rules are measured upstream. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | One validation, at the boundary, in a private table that reads the boundary view and adds `fl_registro_invalido`. The rules are written both as warn expectations and as the source of the flag, with the same predicates (research, Decision 5). Flagged rows go to `workspace.silver.tb_quarentena`, as delivered by the view, with `regras_violadas`. No `DROP ROW`. The `_rescued_data` clauses no longer exist in v1.6.0. Bronze = valid + quarantined is checked in the quickstart. |
| V. Dataset Types and Flows | Yes | DEVIATION | Every dataset is declared as streaming, as v1.6.0 requires in silver: the boundary view reads `STREAM(workspace.bronze.dados_api)`, and both tables are streaming tables over `STREAM(...)`. No materialized view. The pipeline's triggered mode decides that they run as batches. The boundary view is a temporary view, the default for intermediate logic. The private streaming table is justified as the materialized split point (research, Decision 2). `PARTITIONED BY (fl_registro_invalido)` breaks "New datasets MUST NOT use `PARTITIONED BY`"; justified in Complexity Tracking. One dataset per file, named `NN_<dataset>.sql` and numbered from `01` per zone folder, bronze included after the renames. Single source per table, so no `CREATE FLOW`. |
| VI. Record Source and Hash Keys | Yes | PASS | `origem = 'API'` (literal) and `data_carga` on both tables. Hash keys are required on conformed silver tables only. Neither table here is conformed, so no hash key is derived (research, Decision 6). |
| VII. Kimball Dimensional Modeling | No | N/A | No gold dataset. |
| Constraints: platform | Yes | PASS | Serverless, triggered updates, Free Edition. |
| Constraints: catalog and schemas | Yes | PASS | Every persisted name is three-level in `workspace`. The temporary view is pipeline-scoped and unqualified. |
| Constraints: landing zone | Yes | PASS | Not read or written by this feature. |
| Constraints: repository layout | Yes | PASS | Project code in `src/pipeline/01_bronze/` and `02_silver/`, every file with its `NN_` prefix. No auxiliary code. |
| Constraints: naming | Yes | PASS | `vw_bronze_dados_api` follows `vw_<source zone>_<dataset>`. `temp_tb_` for the private staging table and `tb_` for the silver table. Columns are in Portuguese snake_case (`regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga`); source columns keep their names. No explicit flows, so no flow names. |
| Constraints: data, CLI | Yes | PASS | Synthetic data; every command takes `--profile`. |
| Workflow: consult `databricks-pipelines` skill | Yes | PASS | Consulted: `SKILL.md`, `streaming-table-sql.md`, `expectations-sql.md`, `temporary-view-sql.md`. The skill prefers `CLUSTER BY`; the platform rejects it for `BOOLEAN`, which is recorded in Complexity Tracking. |
| Workflow: completion gates | Yes | PLANNED | Gate 1 (validates, update finishes) and gate 2 (data quality tab shows the 4 expectations) are quickstart steps 2 and 4. Gate 3 is quickstart steps 3–4. Gate 4: `origem` populated; hash keys not applicable (Principle VI). Gate 5: no fact. Gate 6: documentation tasks below. |
| Workflow: full refresh / type change | Yes | PASS | Both tables are new. The empty backing table of the first attempt may need a refresh of that table alone if the schema change is refused; that needs the owner's approval first (research, Decision 8). |

**Gate result (pre-research)**: PASS, no deviations (v1.5.0).

**Gate result (post-design, v1.6.0)**: PASS with one justified deviation (Principle V,
`PARTITIONED BY`). Clustering on the flag was planned first, but the platform rejected it
at the first real update (`DELTA_CLUSTERING_COLUMNS_DATATYPE_NOT_SUPPORTED`: a `BOOLEAN`
column does not support data skipping). The owner then decided to partition, as the
original request said. See Complexity Tracking. The amendment to v1.6.0 added the boundary
view and the numbering and removed the rescued-data rule; the design follows all three.

## Project Structure

### Documentation (this feature)

```text
specs/004-api-quarantine/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── silver-validation-quarantine.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    ├── 01_bronze/                          # RENAMED files, content unchanged (feature 003)
    │   ├── 01_dados_api.sql                # was dados_api.sql
    │   ├── 02_dados_files.sql              # was dados_files.sql
    │   └── 03_dados_database.sql           # was dados_database.sql
    └── 02_silver/                          # NEW folder
        ├── 01_vw_bronze_dados_api.sql      # NEW: boundary view, drops source_file_name and _rescued_data
        ├── 03_temp_tb_validacao_api.sql    # NEW: private validation table, 3 rules, flag, partitioned
        └── 04_tb_quarentena.sql            # NEW: quarantine of flagged API events

doc/
├── pipeline-reference.md                   # CHANGED: bronze file names; silver sections for the view and both tables
├── architecture.md                         # CHANGED: graph and feature table point to src/pipeline/02_silver/
├── README.md                               # CHANGED: repository layout lists the numbered files
└── known-issues.md                         # CHANGED: the old quarantine's catalog-name entry is resolved
```

**Structure Decision**: the three definitions are project code and open the `02_silver/`
zone folder. Each file is named `NN_<dataset>.sql`, numbered in data-flow order (view,
validation, quarantine). The bronze files gain the same prefixes. The pipeline's glob picks
the folder up, so `explorations/setup/03_pipeline_dev.json` does not change. In the
workspace, the old unnumbered files must be deleted after the upload, because
`import-dir` does not remove them (research, Decision 7).

## Design Notes for Implementation

These carry the decisions of [research.md](research.md) into the task phase.

- **Consult the skill first.** Read `databricks-pipelines` (`streaming-table-sql.md`,
  `expectations-sql.md`, `temporary-view-sql.md`) before writing the files, as the
  constitution requires.
- **The view does one thing.** `SELECT * EXCEPT (source_file_name, _rescued_data) FROM
  STREAM(workspace.bronze.dados_api)`. No filter, cast, rename, rule or added column.
- **Two parallel lists in the validation file.** Write the three `CONSTRAINT` clauses and
  the three `CASE WHEN NOT (...)` lines in the same order, with identical conditions.
  Lay them out so that a reviewer can compare them line by line. The conditions are
  exactly those of [data-model.md](data-model.md#validation-rules).
- **Select list order.** `*` first, then `regras_violadas`, `fl_registro_invalido`,
  `origem`, `data_carga`. The quarantine file uses `*`, keeping every validation column, followed by
  `current_timestamp() AS data_carga_quarentena` (Principle IV, v1.6.0).
- **Comments in Portuguese**, one short header comment per file and the dataset
  `COMMENT`, matching the bronze files.
- **Renames keep content.** `git mv` the bronze files; `git diff -M` must show pure
  renames.
- **Workspace clean-up.** After `import-dir`, delete the four unnumbered files left in the
  workspace, then confirm each folder lists exactly the repository's files.
- **Dry run before the real run.** If it rejects the lateral alias, apply the subquery
  fallback of the contract. Report anything else to the owner. If the real run refuses
  the schema change of the empty private table, ask the owner before refreshing it alone.
- **Documentation replaces, not appends.** `doc/pipeline-reference.md` describes the
  earlier pipeline's `vw_bronze_dados_api`, `temp_tb_validacao_api` ("partitioned by
  `fl_registro_invalido`", three rules) and `tb_quarentena`. Rewrite those three
  descriptions for this design, including `regras_violadas`, the expectations and the
  consumer rule for conformed tables, and rename the bronze file links. In
  `doc/architecture.md`, keep `vw_bronze_dados_api` in the API path of the graph, point
  its node and the quarantine rows of the feature table to the new files, and rename the
  bronze links. In `doc/README.md`, list the numbered files. In `doc/known-issues.md`,
  remove the `04_tb_quarentena.sql` row of the catalog mismatch and its paragraph, since
  the new quarantine reads `workspace`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| `PARTITIONED BY (fl_registro_invalido)` on `workspace.silver.temp_tb_validacao_api`, against Principle V ("New datasets MUST NOT use `PARTITIONED BY`. Where physical layout matters, use `CLUSTER BY`.") | The request asks to partition by the flag, so that the quarantine reads only the `true` partition and the conformed tables only the `false` one. The owner confirmed partitioning on 2026-10-18 after clustering failed. A Boolean column gives exactly two partitions, so the small-file and over-partitioning risks the rule guards against do not arise. | `CLUSTER BY (fl_registro_invalido)`, the constitution's prescribed form: rejected by the platform with `DELTA_CLUSTERING_COLUMNS_DATATYPE_NOT_SUPPORTED`, because `BOOLEAN` columns do not support data skipping. Clustering on a derived non-Boolean copy of the flag (for example an `INT`): rejected, because it adds a column that exists only for layout and is carried into quarantine. No layout clause at all: rejected by the owner, since the request names the partitioning. |

The exception is bounded to this table. If it should become a standing rule (for example
"Boolean split flags of validation tables may be partitioned"), it needs an amendment
through `/speckit-constitution`.
