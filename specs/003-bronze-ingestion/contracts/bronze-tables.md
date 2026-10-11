# Contract: Bronze Table Definitions and the Development Pipeline

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-11

The feature exposes two things: three table definitions that later layers will read, and
the settings of the pipeline that runs them. This document fixes both.

## Table definitions

One file per table, each holding exactly one statement.

| File | Table | Reads | Format options |
|---|---|---|---|
| `src/pipeline/01_bronze/dados_api.sql` | `workspace.bronze.dados_api` | `/Volumes/workspace/bronze/landing/stream/` | `format => 'json'` |
| `src/pipeline/01_bronze/dados_files.sql` | `workspace.bronze.dados_files` | `/Volumes/workspace/bronze/landing/files/` | `format => 'csv'`, `header => true`, `sep => ','` |
| `src/pipeline/01_bronze/dados_database.sql` | `workspace.bronze.dados_database` | `/Volumes/workspace/bronze/landing/database/` | `format => 'csv'`, `header => true`, `sep => ','` |

### Shape every statement must have

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH STREAMING TABLE`, with the three-level table name |
| Description | a `COMMENT` in Portuguese saying which source the table holds |
| Property | `TBLPROPERTIES ("quality" = "bronze")` |
| Source | `STREAM read_files(<path>, <format options>)` and nothing else in the `FROM` clause |
| Select list | `current_timestamp() AS processing_time`, `_metadata.file_path AS source_file_name`, `*`, in that order |

### What a statement must not contain

| Forbidden | Why |
|---|---|
| `WHERE`, `DISTINCT`, `GROUP BY`, joins | bronze does not filter, deduplicate or combine (FR-010) |
| `CAST`, column aliases on source columns, `EXCEPT` | bronze does not cast, rename or drop columns (FR-005, FR-010) |
| `CONSTRAINT ... EXPECT` with `DROP ROW` or `FAIL UPDATE` | bronze removes no row and stops no run (FR-010) |
| `LIVE`, `cloud_files`, `CREATE OR REPLACE`, `PARTITIONED BY` | legacy or non-pipeline syntax (constitution, Principles II and V) |
| a schema, `schemaHints`, `schemaLocation`, a checkpoint path | types are inferred; locations are managed by the pipeline |
| any reference to a catalog other than `workspace` | constitution, catalog constraint |

### What consumers may rely on

- The table names and the names of the source columns listed in
  [../data-model.md](../data-model.md).
- `processing_time` and `source_file_name` exist and are never null.
- `_rescued_data` exists; a non-null value marks a record that did not fit the schema.
- Rows are only ever added. A row, once present, does not change.
- A source file contributes its rows exactly once, unless the table is fully refreshed.

Consumers must not rely on column types staying fixed: they are inferred, and a new column
in a source appears in the table after the pipeline picks up the change.

## Development pipeline

Settings kept in `explorations/setup/03_pipeline_dev.json`.

| Setting | Value | Reason |
|---|---|---|
| `name` | `lakeflow_dataslight_dev` | distinct from the old pipeline |
| `catalog` | `workspace` | the project's single catalog |
| `schema` | `bronze` | default for unqualified names; the tables are fully qualified anyway |
| `serverless` | `true` | Free Edition |
| `continuous` | `false` | triggered runs; the stream is simulated by files |
| `development` | `true` | fail fast, no production retries |
| `channel` | `CURRENT` | only generally available features are used |
| `configuration` | `pipelines.numUpdateRetryAttempts = 0`, `pipelines.maxFlowRetryAttempts = 0` | a failure shows at once |
| `libraries` | one glob: `/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline/**` | picks up every layer folder as it is added |

### Operations

| Operation | Command | Notes |
|---|---|---|
| Upload source | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile <profile>` | repeat after every code change |
| Create (once) | `databricks pipelines create --json @explorations/setup/03_pipeline_dev.json --profile <profile>` | returns the `pipeline_id` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile <profile>` | checks the code, materializes nothing |
| Run | `databricks pipelines start-update <pipeline_id> --profile <profile>` | returns an `update_id` |
| Wait | `databricks pipelines get-update <pipeline_id> <update_id> --profile <profile>` | poll `.update.state` until `COMPLETED`, `FAILED` or `CANCELED` |
| Diagnose | `databricks pipelines list-pipeline-events <pipeline_id> --profile <profile>` | the cause is in `error.exceptions[0].message` of the `ERROR` events |

**Never part of a normal run**: `--full-refresh`. It discards what was ingested and reads
every file again, and needs the owner's approval.

## Mapping to the specification

| Spec item | Covered by |
|---|---|
| FR-001, FR-002 | the three files and the table of definitions |
| FR-003, FR-004 | statement and source rows of the shape table |
| FR-005, FR-008, FR-010 | `*` in the select list; the forbidden list |
| FR-006, FR-007 | select list |
| FR-009 | property row |
| FR-011, FR-012 | streaming table over `STREAM read_files`; "what consumers may rely on" |
| FR-013, FR-014 | one statement per file, file named after the table, under `src/pipeline/01_bronze/` |
| FR-015 | the statements only read from the volume |
| FR-016 | documentation task (see plan) |
