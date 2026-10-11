# Research: Bronze Ingestion of the Three Landing Sources

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-11

Findings marked *observed* were read from the target environment on 2026-10-11 with
read-only queries (profile `databricks-free`, host `dbc-7e0f02e0-ff06`). Nothing was
changed there.

As the constitution requires before pipeline code, the `databricks-pipelines` skill was
consulted: `SKILL.md` and the references `sql-basics`, `streaming-table-sql`,
`auto-loader-sql`, `options-json`, `options-csv`, `dlt-migration` and
`2-rapid-iteration-with-cli`.

## State of the target environment (observed)

The landing volume, empty when feature 002 finished, now holds generated data.

| Source folder | Data files | Records | Other entries in the folder |
|---|---|---|---|
| `stream/` | 8 JSON files | 2,550,955 | `_spark_metadata/` |
| `files/` | 1 CSV file | 100,000 | none |
| `database/` | 1 CSV file | 3 | `_SUCCESS`, `_committed_*`, `_started_*` |

| Fact | Value |
|---|---|
| Sibling of the source folders | `_checkpoint_stream/`, the stream generator's bookkeeping |
| Entries whose names start with `_` | not read as data: a batch read of each folder counted exactly the data files above |
| Rescued records today | 0 in all three sources |
| File path reported by the file metadata | has the form `dbfs:/Volumes/workspace/bronze/landing/<folder>/<file>` |
| Tables in `workspace.bronze` | none |
| Pipelines in the workspace | one, `New Pipeline 2026-08-27 17:09`, idle, pointing at `/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow/code_tips/**`, a folder that is no longer in the repository |
| Bundle | `databricks.yml` defines a `dev` target in development mode and no resources |

Inferred columns of each source are listed in [data-model.md](data-model.md).

## Decision 1: statement form

**Decision**: each table is one statement in current Lakeflow syntax:
`CREATE OR REFRESH STREAMING TABLE workspace.bronze.<table>`, with a `COMMENT`,
`TBLPROPERTIES ("quality" = "bronze")`, and `AS SELECT ... FROM STREAM read_files(...)`.

**Rationale**: this is what the request asks for (streaming table, Auto Loader, the
`quality` property) in the form Principle II requires. `STREAM read_files(...)` is Auto
Loader in SQL; without `STREAM` the read would be a batch read and the statement would be
rejected for a streaming table. A single `AS SELECT` is the right shape for one source per
table; append flows are for several sources feeding one table, which is not the case here.

**Alternatives considered**:
- *`CREATE OR REFRESH STREAMING LIVE TABLE ... FROM cloud_files(...)`*, the form of the
  project's earlier code. Rejected: legacy syntax, forbidden by Principle II.
- *A materialized view over `read_files`*. Rejected: it would re-read every file on each
  run and gives no exactly-once guarantee, against FR-003, FR-011 and FR-012.

## Decision 2: select list and the two lineage columns

**Decision**: the select list is
`current_timestamp() AS processing_time`, `_metadata.file_path AS source_file_name`, then
`*`. The two lineage columns come first, followed by every source column and
`_rescued_data`.

**Rationale**: the two expressions are exactly the ones named in the request. `*` keeps
every source column under its own name (FR-005) and brings `_rescued_data`, which
`read_files` adds when it infers the schema (*observed*). Putting the lineage columns first
keeps the column order of the project's earlier bronze tables, which the documentation and
notebooks show.

**Note on `source_file_name`**: its value is the full path with the `dbfs:` scheme, not
only the file name. The column name is kept because the request and the constitution name
it.

## Decision 3: file options per source

**Decision**:

| Table | Path | Options |
|---|---|---|
| `dados_api` | `/Volumes/workspace/bronze/landing/stream/` | `format => 'json'` |
| `dados_files` | `/Volumes/workspace/bronze/landing/files/` | `format => 'csv'`, `header => true`, `sep => ','` |
| `dados_database` | `/Volumes/workspace/bronze/landing/database/` | `format => 'csv'`, `header => true`, `sep => ','` |

No other option is set.

**Rationale**:
- Column types are inferred. `read_files` infers types by default, so the explicit
  `cloudFiles.inferColumnTypes` of the earlier code is not needed.
- `header` makes the first line give the column names instead of becoming a row; `sep` is
  stated because the generators write commas explicitly.
- The schema location and checkpoints are managed by the pipeline and must not be set.
- Marker files, `_spark_metadata/` and names starting with `_` are skipped by the file
  source (*observed*), and `_checkpoint_stream/` is a sibling of the source folders, not
  inside any of them, so no filter is needed.

**Alternatives considered**:
- *`schemaHints` or a declared schema*. Rejected by the spec's assumption that types are
  inferred. This has one consequence, recorded in Decision 6.
- *One definition reading the whole volume with a glob*. Rejected: three sources with
  different formats and shapes belong in three tables.

## Decision 4: names and file layout

**Decision**: the tables are referenced by three-level name. The files are
`src/pipeline/01_bronze/dados_api.sql`, `dados_files.sql` and `dados_database.sql`.

**Rationale**: the constitution requires three-level names for persisted datasets, one
dataset per file, the file named after the dataset, and pipeline SQL under
`src/pipeline/01_bronze/`. The earlier files carried numeric prefixes
(`01_bronze_dados_database.sql`); those are dropped because the layer folder already gives
the order and the rule is "named after that dataset".

## Decision 5: how the pipeline is created and run

**Decision**: a new development pipeline created with the CLI, without a bundle resource.

1. Its settings are kept in the repository as `explorations/setup/03_pipeline_dev.json`:
   name `lakeflow_dataslight_dev`, catalog `workspace`, default schema `bronze`,
   serverless, triggered, development mode, channel `CURRENT`, both retry settings at `0`,
   and a library glob over the uploaded `src/pipeline/**`.
2. The source is uploaded with `databricks workspace import-dir src/pipeline
   /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite`.
3. The pipeline is created once with `databricks pipelines create --json @<file>`, checked
   with `start-update --validate-only`, then run with `start-update`. The update, not the
   pipeline, is polled until it reaches a terminal state.

**Rationale**:
- The spec puts "managing the pipeline as a deployable resource" in a later step, and the
  skill's guidance for demo and iteration work is the CLI workflow.
- Development mode and zero retries make a failure show immediately instead of after
  several silent retries.
- Channel `CURRENT` instead of the skill's iteration default `PREVIEW`: these three
  statements use only generally available features, and a stable channel is the safer
  choice for a pipeline shown live.
- The settings file is auxiliary setup, so it sits in `explorations/setup/` with the next
  step number.
- A dedicated workspace folder (`lakeflow_dev`) avoids writing into the folder the old
  pipeline reads.

**The existing pipeline is left alone**: `New Pipeline 2026-08-27 17:09` defined the same
table names from the old code. Its tables no longer exist, so the new pipeline can create
and own them. If the old pipeline were run again it would fail, since a table belongs to
one pipeline. Deleting it is the owner's decision and outside this feature.

**Alternatives considered**:
- *Bundle resource in `databricks.yml`*. Deferred, not rejected: it is the right home once
  the pipeline has more than a bronze layer, and the JSON maps directly onto it.
- *Reusing the existing pipeline by repointing its libraries*. Rejected: it is not in
  development mode, defaults to the `default` schema, and carries the history of the old
  code.

## Decision 6: an empty or missing source folder

**Decision**: data for all three sources must exist before the first run. If a folder is
empty or missing, that table's flow fails with the platform's message naming the path; the
definitions do nothing to prevent it.

**Rationale**: with inferred types there are no files to infer the columns from, so no
table can be built. The only way to create an empty table is a declared schema, which the
spec excludes. The spec's edge case was reworded on 2026-10-11 to say this.

**Status**: not provoked. All three folders hold data today, and emptying one to see the
exact message is not worth the risk to the generated data.

## Decision 7: how the result is validated

**Decision**: each success criterion is checked with a query, comparing against the landing
files as they are at that moment, not against fixed numbers:

- row counts: `count(*)` of each table equals `count(*)` of a batch `read_files` over the
  same folder with the same options (SC-002);
- lineage: no null `processing_time` or `source_file_name`, and the distinct
  `source_file_name` values equal the distinct `_metadata.file_path` values of the batch
  read (SC-003, SC-004);
- columns: the table's columns are the batch read's columns plus the two lineage columns
  (SC-005);
- property: `SHOW TBLPROPERTIES` returns `quality = bronze` (SC-008);
- incremental: a second run adds 0 rows; then one small CSV file with one `update` row, in
  the exact shape the course generator writes, is uploaded to `database/`, and the next
  run must add 1 row to `dados_database` and 0 to the other two (SC-006, SC-007).

**Rationale**: the stream source has 2.5 million rows across files whose names change on
every generation, so fixed expectations would not survive a regeneration. The `database/`
source is the right place for the incremental test because it has 3 rows and the file
added is the same change the talk's change-data-capture demo makes.

**Clean-up after the incremental test**: bronze is append-only, so the test row stays
until the table is rebuilt. Removing the test file and running a full refresh of
`dados_database` alone restores it to the 3 original rows. A full refresh destroys
streaming state, so the constitution requires the owner's approval; the owner may also
choose to keep the row.

## Open questions

None that block the design. Two points are confirmed during implementation and handled
either way: the exact flag for refreshing a single table, and whether the workspace folder
`lakeflow_dev` is free.
