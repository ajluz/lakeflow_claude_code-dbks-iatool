# Implementation Plan: Bronze Ingestion of the Three Landing Sources

**Branch**: `003-bronze-ingestion` | **Date**: 2026-10-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-bronze-ingestion/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Load each of the three landing sources into its own streaming table in `workspace.bronze`,
unchanged, with two lineage columns (`processing_time`, `source_file_name`) and the
property `quality = bronze`.

Technical approach, from [research.md](research.md): three SQL files under
`src/pipeline/01_bronze/`, one statement each, in current Lakeflow syntax:
`CREATE OR REFRESH STREAMING TABLE ... AS SELECT current_timestamp() AS processing_time,
_metadata.file_path AS source_file_name, * FROM STREAM read_files(...)`. A development
pipeline, created with the CLI from a settings file kept in `explorations/setup/`, runs
them. Validation compares each table against a batch read of the same landing folder, then
proves incremental behavior by delivering one extra file.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`STREAMING TABLE`, `STREAM read_files`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless); Auto Loader
through `read_files`; Unity Catalog; Databricks CLI v1.11.0; `jq` for the run commands

**Storage**: reads files from the managed volume `workspace.bronze.landing`; writes three
managed streaming tables in `workspace.bronze`

**Testing**: pipeline dry run (`--validate-only`), then the queries of
[quickstart.md](quickstart.md), which compare each table with a batch read of its landing
folder. No test framework

**Target Platform**: Databricks Free Edition workspace `dbc-7e0f02e0-ff06`

**Project Type**: data pipeline (project code under `src/`), plus one auxiliary settings
file for the development pipeline

**Performance Goals**: the first run ingests the current landing data (about 2.65 million
rows, most of them in 8 JSON files) in one triggered update; a run with no new files
finishes without reading any data file again

**Constraints**: bronze changes nothing in the data; types are inferred; no option beyond
format, header and separator; nothing is written to the landing volume; no full refresh
without the owner's approval; CLI profile always passed explicitly

**Scale/Scope**: 3 SQL files, 1 pipeline settings file, 3 tables, 3 documentation updates

No item is marked NEEDS CLARIFICATION. Facts about the landing data and the workspace were
read on 2026-10-11 and are recorded in [research.md](research.md).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.5.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | The three tables are append-only streaming tables in `workspace.bronze`. They keep every source column, add only `processing_time`, `source_file_name` and Auto Loader's `_rescued_data`, and do not filter, cast, rename, deduplicate or drop. Each carries `TBLPROPERTIES ("quality" = "bronze")`. They read only the landing volume. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Three `.sql` files, declarative, in current syntax. None of the legacy forms the principle lists is used: no `LIVE`, no `cloud_files`, no `CREATE OR REPLACE`, no `input_file_name()`. |
| III. Data Quality Through Expectations | Yes | PASS | Bronze declares no `DROP ROW` or `FAIL UPDATE` expectation, as the principle requires. No quality rule is expressed as a bare filter, because there is no filter. Quality rules start in silver. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | Nothing is discarded. `_rescued_data` is kept on every table so that the silver step can route rescued rows to quarantine. |
| V. Dataset Types and Flows | Yes | PASS | Incrementally growing file sources feed streaming tables through `STREAM read_files(...)`. One source per table, so a single `AS SELECT` and no append flows. No `PARTITIONED BY`. One dataset per file, each file named after its dataset. |
| VI. Record Source and Hash Keys in Silver | No | N/A | No silver table. |
| VII. Kimball Dimensional Modeling in Gold | No | N/A | No gold table. |
| Constraints: platform | Yes | PASS | Serverless pipeline; runs on Free Edition with triggered updates over files. |
| Constraints: catalog and schemas | Yes | PASS | Tables are referenced by three-level name in `workspace.bronze`; no other catalog. |
| Constraints: landing zone | Yes | PASS | The definitions read `workspace.bronze.landing`, one folder per source, and never write to it. The validation's single test file is delivered by the owner's CLI, not by pipeline code. |
| Constraints: repository layout | Yes | PASS | Project code in `src/pipeline/01_bronze/`. The pipeline settings file is auxiliary setup and goes in `explorations/setup/` as `03_`. |
| Constraints: naming | Yes | PASS | Table and column names are lowercase snake_case in Portuguese, except the two lineage columns, whose names the constitution itself fixes. |
| Constraints: data | Yes | PASS | Synthetic data only. |
| Constraints: CLI | Yes | PASS | Every command takes `--profile`; none is stored in a file. |
| Workflow: consult `databricks-pipelines` skill | Yes | PASS | Consulted before design; the references read are listed in research.md. One deliberate difference from the skill's iteration defaults (channel `CURRENT`) is justified there. |
| Workflow: completion gates | Yes | PLANNED | Gate 1 (pipeline validates and an update finishes) and gate 6 (documentation) are tasks of this feature. Gate 3 is covered as far as bronze goes: table rows equal landing records. Gates 2, 4 and 5 concern expectations, silver keys and facts, which do not exist yet. |
| Workflow: full refresh needs approval | Yes | PASS | Normal runs never use it. The optional clean-up of the test row refreshes one 3-row table and is run only with the owner's approval. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations. The contract in
[contracts/bronze-tables.md](contracts/bronze-tables.md) turns the bronze rules of
Principle I into an explicit list of what a statement must and must not contain.

## Project Structure

### Documentation (this feature)

```text
specs/003-bronze-ingestion/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── bronze-tables.md # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/                                 # project code: what the pipeline deploys and runs
└── pipeline/
    └── 01_bronze/
        ├── dados_api.sql            # NEW: site events, from landing/stream/ (JSON)
        ├── dados_files.sql          # NEW: corporate sales, from landing/files/ (CSV)
        └── dados_database.sql       # NEW: course catalog changes, from landing/database/ (CSV)

explorations/                        # auxiliary code
└── setup/
    ├── 01_schemas.sql               # unchanged
    ├── 01_schemas_verify.sql        # unchanged
    ├── 02_landing_volume.sql        # unchanged
    ├── 02_landing_volume_verify.sql # unchanged
    └── 03_pipeline_dev.json         # NEW: settings of the development pipeline

doc/
├── pipeline-reference.md            # CHANGED: bronze section describes the three new files
├── getting-started.md               # CHANGED: how to upload, create and run the pipeline
└── README.md                        # CHANGED: repository layout lists src/pipeline/ and 03_
```

**Structure Decision**: the three definitions are project code and open the `src/` folder,
in `src/pipeline/01_bronze/`, as the constitution's repository layout prescribes. The
pipeline points at `src/pipeline/**`, so silver and gold folders added later are picked up
without changing its settings. The settings file is auxiliary and continues the numbered
setup steps.

## Design Notes for Implementation

These carry the decisions of [research.md](research.md) into the task phase.

- **Three near-identical files.** They differ only in table name, comment, folder and
  format options. Keep them visibly parallel: same layout, same line order.
- **Exactly the contract's shape.** Lineage columns first, then `*`. No other expression,
  clause or option.
- **Paths end with a slash** and name the folder, never a file or a glob.
- **Comments in Portuguese**, one short header comment per file and the table `COMMENT`,
  matching the setup scripts.
- **Check before creating.** Before `pipelines create`, confirm that the workspace folder
  `lakeflow_dev` and a pipeline named `lakeflow_dataslight_dev` do not already exist, so
  that a re-run of the tasks does not create a second pipeline.
- **Dry run before the first real run.** `--validate-only` catches syntax and reference
  errors without touching data.
- **Poll the update, not the pipeline**, and on failure read
  `error.exceptions[0].message` from the events.
- **The old pipeline is not touched.** `New Pipeline 2026-08-27 17:09` stays as it is;
  whether to delete it is raised with the owner in the completion report.
- **Documentation scope.** `doc/pipeline-reference.md` still describes the earlier
  `code_tips/` pipeline in full. This feature rewrites its Bronze section only; silver and
  gold stay until their features replace them, with a note saying so.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations.
