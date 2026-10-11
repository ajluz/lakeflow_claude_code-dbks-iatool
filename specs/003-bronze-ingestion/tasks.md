---

description: "Task list for feature 003-bronze-ingestion"
---

# Tasks: Bronze Ingestion of the Three Landing Sources

**Input**: Design documents from `/specs/003-bronze-ingestion/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/bronze-tables.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching scenario of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pipeline SQL (project code): `src/pipeline/01_bronze/`
- Pipeline settings (auxiliary setup): `explorations/setup/`
- Documentation: `doc/`
- All paths below are relative to the repository root

## Conventions for every task

- **Statement shape**, fixed by contracts/bronze-tables.md. Every definition file holds one
  short header comment in Portuguese and exactly one statement of this form, with nothing
  added:

  ```sql
  CREATE OR REFRESH STREAMING TABLE workspace.bronze.<table>
  COMMENT '<description in Portuguese>'
  TBLPROPERTIES ("quality" = "bronze")
  AS
  SELECT
    current_timestamp() AS processing_time,
    _metadata.file_path AS source_file_name,
    *
  FROM STREAM read_files(
    '/Volumes/workspace/bronze/landing/<folder>/',
    <format options>
  );
  ```

- **Forbidden in a definition**: `WHERE`, `DISTINCT`, `GROUP BY`, joins, `CAST`, `EXCEPT`,
  aliases on source columns, `CONSTRAINT`, `LIVE`, `cloud_files`, `CREATE OR REPLACE`,
  `PARTITIONED BY`, a declared schema, `schemaHints`, `schemaLocation`, a checkpoint path,
  and any catalog other than `workspace`.
- **Why the files are complete from the start**: the lineage columns must exist before the
  first run. A column added to a streaming table after rows were ingested would be null on
  those rows, which the spec forbids. The three files are therefore written in full in the
  Foundational phase, and each user story is delivered by running and proving a part of
  their behavior.
- **Running against the workspace**: ask the owner which CLI profile to use before the
  first command and pass `--profile <profile>` every time. Never choose a profile on the
  owner's behalf.
- **Polling**: after `start-update`, poll `databricks pipelines get-update <pipeline_id>
  <update_id>` and read `.update.state` until `COMPLETED`, `FAILED` or `CANCELED`. On
  `FAILED`, read `error.exceptions[0].message` of the `ERROR` rows returned by
  `databricks pipelines list-pipeline-events <pipeline_id>` and fix the cause; do not
  simply run again.
- **Never** pass `--full-refresh` in these tasks except where a task says so and the owner
  has approved it.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the folders and the pipeline settings file

- [X] T001 Create the folder `src/pipeline/01_bronze/`
- [X] T002 [P] Create `explorations/setup/03_pipeline_dev.json` with exactly these settings: `"name": "lakeflow_dataslight_dev"`, `"catalog": "workspace"`, `"schema": "bronze"`, `"serverless": true`, `"continuous": false`, `"development": true`, `"channel": "CURRENT"`, `"configuration": {"pipelines.numUpdateRetryAttempts": "0", "pipelines.maxFlowRetryAttempts": "0"}`, and `"libraries": [{"glob": {"include": "/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline/**"}}]`; the file must be valid JSON with no comments

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the three definitions, complete, and the checks that the environment is ready

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Create `src/pipeline/01_bronze/dados_api.sql` in the statement shape above: table `workspace.bronze.dados_api`; `COMMENT 'Eventos de acesso ao site recebidos da API, exatamente como chegaram.'`; path `/Volumes/workspace/bronze/landing/stream/`; options `format => 'json'`; header comment saying the source is the site API, delivered as JSON files in the `stream/` folder
- [X] T004 [P] Create `src/pipeline/01_bronze/dados_files.sql` in the statement shape above: table `workspace.bronze.dados_files`; `COMMENT 'Vendas corporativas enviadas por empresas parceiras, exatamente como chegaram.'`; path `/Volumes/workspace/bronze/landing/files/`; options `format => 'csv'`, `header => true`, `sep => ','`; header comment saying the source is partner companies, delivered as CSV files in the `files/` folder
- [X] T005 [P] Create `src/pipeline/01_bronze/dados_database.sql` in the statement shape above: table `workspace.bronze.dados_database`; `COMMENT 'Mudanças do catálogo de cursos (insert, update, delete), exatamente como chegaram.'`; path `/Volumes/workspace/bronze/landing/database/`; options `format => 'csv'`, `header => true`, `sep => ','`; header comment saying the source is the course catalog database, delivered as a change feed in CSV files in the `database/` folder
- [X] T006 Review `src/pipeline/01_bronze/dados_api.sql`, `dados_files.sql` and `dados_database.sql` together: the three are line-for-line parallel and differ only in table name, comment, folder and format options; each has `processing_time`, then `source_file_name`, then `*`, in that order; none contains anything from the forbidden list
- [X] T007 Confirm the environment is ready, changing nothing: run the combined check `databricks experimental aitools tools query explorations/setup/01_schemas_verify.sql explorations/setup/02_landing_volume_verify.sql --profile <profile> --output json | jq -r '.[].rows[] | @tsv'` and confirm no row says `FAIL`; list `dbfs:/Volumes/workspace/bronze/landing/stream`, `files` and `database` with `databricks fs ls` and confirm each holds at least one entry whose name does not start with `_`; if a folder is missing or empty, stop and ask the owner to generate that source's data
- [X] T008 Confirm nothing is in the way, changing nothing: `databricks pipelines list-pipelines --profile <profile>` shows no pipeline named `lakeflow_dataslight_dev`; `databricks workspace list /Workspace/Users/arthur.luz@dataslight.com.br --profile <profile>` shows no entry named `lakeflow_dev`; `databricks tables list workspace bronze --profile <profile>` shows none of `dados_api`, `dados_files`, `dados_database`; if any exists, stop and ask the owner how to proceed

**Checkpoint**: the definitions are written and reviewed; the environment is ready

---

## Phase 3: User Story 1 - Ingest each landing source into its own bronze table (Priority: P1) 🎯 MVP

**Goal**: three bronze tables exist, one per source, each holding every record of its landing files with every source column unchanged.

**Independent Test**: quickstart.md Scenario 1. After one run, `dados_api`, `dados_files` and `dados_database` exist, and for each the table's row count equals the count of a batch read of its landing folder.

### Implementation for User Story 1

- [X] T009 [US1] Upload the pipeline source with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile <profile>` and confirm with `databricks workspace list` that the three `.sql` files are in `.../lakeflow_dev/src/pipeline/01_bronze` as files, not notebooks
- [X] T010 [US1] Create the pipeline with `databricks pipelines create --json @explorations/setup/03_pipeline_dev.json --profile <profile>`, record the returned `pipeline_id` in the Implementation notes of this file, and confirm with `databricks pipelines get <pipeline_id>` that the settings match `explorations/setup/03_pipeline_dev.json`
- [X] T011 [US1] Run a dry run with `databricks pipelines start-update <pipeline_id> --validate-only --profile <profile>`, poll that update to a terminal state, and confirm it is `COMPLETED` and that `databricks tables list workspace bronze` still shows no table; on `FAILED`, read the events, fix the definition in `src/pipeline/01_bronze/`, upload again and repeat
- [X] T012 [US1] Run the first real update with `databricks pipelines start-update <pipeline_id> --profile <profile>`, poll that update to a terminal state, and confirm it is `COMPLETED` and that `databricks tables list workspace bronze` shows `dados_api`, `dados_files` and `dados_database`
- [X] T013 [US1] Validate row counts as in quickstart.md Scenario 1: for each table, one query returning `(SELECT count(*) FROM workspace.bronze.<table>)` beside `(SELECT count(*) FROM read_files('<folder>', <same format options>))`, and confirm the two numbers are equal for all three; record the three counts in the Implementation notes of this file
- [X] T014 [US1] Validate that nothing was changed in the data: run `DESCRIBE workspace.bronze.<table>` for each table and confirm the columns are `processing_time`, `source_file_name`, then the source columns listed in data-model.md under their original names, then `_rescued_data`; run `SELECT payload.info_produto.product_name, count(*) FROM workspace.bronze.dados_api GROUP BY ALL` and confirm it returns course names without error, proving the nesting is preserved

**Checkpoint**: User Story 1 is functional; the three bronze tables hold the landing data

---

## Phase 4: User Story 2 - Know when and from where every row came (Priority: P1)

**Goal**: every row carries a processing time and the path of its source file, and every table carries the `quality` property.

**Independent Test**: quickstart.md Scenario 2. No null in either lineage column; the distinct file paths in each table match the data files of its folder; `quality` is `bronze` on all three.

### Implementation for User Story 2

- [X] T015 [US2] For each of the three tables, run `SELECT count(*) AS linhas, count_if(processing_time IS NULL) AS sem_processing_time, count_if(source_file_name IS NULL) AS sem_source_file_name, count(DISTINCT source_file_name) AS arquivos FROM workspace.bronze.<table>` and confirm both null counts are 0
- [X] T016 [US2] For each of the three tables, confirm the set of `source_file_name` values equals the set of `_metadata.file_path` values of a batch `read_files` over its folder with the same format options (a query returning the rows of each set that are missing from the other must return none), after stripping the `dbfs:` prefix that the batch read adds, and that every value starts with `/Volumes/workspace/bronze/landing/` followed by that table's folder (`stream/`, `files/` or `database/`)
- [X] T017 [US2] For each of the three tables, run `SHOW TBLPROPERTIES workspace.bronze.<table> ('quality')` and confirm the value is `bronze`; confirm with `databricks tables get workspace.bronze.<table>` that each is a streaming table carrying its Portuguese comment

**Checkpoint**: User Stories 1 and 2 hold; every row is traceable

---

## Phase 5: User Story 3 - Pick up new files without reloading old ones (Priority: P2)

**Goal**: a run ingests only files that arrived since the previous run.

**Independent Test**: quickstart.md Scenario 3. A second run with no new files leaves all three counts unchanged; after one new file in `database/`, the next run adds exactly 1 row to `dados_database` and nothing to the other two.

### Implementation for User Story 3

- [X] T018 [US3] Record the three row counts, run a second update with `databricks pipelines start-update <pipeline_id> --profile <profile>` and no new files, poll it to `COMPLETED`, and confirm the three counts are unchanged
- [X] T019 [US3] With the owner's approval, deliver one new file: write a local CSV with the header `curso_uuid,nome_curso,nivel_curso,valor_curso,change_type,timestamp_change` and the single row `6532cdca76d4a7e6f10f71be7eb74668,Construindo um Data Lakehouse com SQL e DLT,beginner,147.0,update,2026-10-11T23:59:59.000Z`, and copy it with `databricks fs cp` to `dbfs:/Volumes/workspace/bronze/landing/database/zz_teste_bronze_update.csv`
- [X] T020 [US3] Run a third update, poll it to `COMPLETED`, and confirm: `dados_database` grew by exactly 1 row; `dados_api` and `dados_files` are unchanged; the new row has `change_type = 'update'`, `valor_curso = 147.0`, a `source_file_name` ending in `zz_teste_bronze_update.csv`, a null `_rescued_data`, and a `processing_time` later than the maximum `processing_time` of the other rows of the table
- [X] T021 [US3] Ask the owner whether to keep the test row or remove it. To remove it: delete the file with `databricks fs rm dbfs:/Volumes/workspace/bronze/landing/database/zz_teste_bronze_update.csv`, run a full refresh of `dados_database` only with `databricks pipelines start-update <pipeline_id> --json '{"full_refresh_selection": ["dados_database"]}'` (the CLI has no flag for a single table), poll it to `COMPLETED`, and confirm that table's count equals its landing files again and the other two tables are unchanged. Record the owner's choice and the outcome in the Implementation notes of this file

**Checkpoint**: all three user stories hold; ingestion is incremental

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: the documentation required by FR-016 and the final review

- [X] T022 [P] In `doc/pipeline-reference.md`, rewrite the `## Bronze` section to describe the three tables as built: the files `src/pipeline/01_bronze/dados_api.sql`, `dados_files.sql` and `dados_database.sql`; that each is a streaming table loaded with Auto Loader through `STREAM read_files`; the folder and format of each; the two lineage columns and where their values come from, noting that `source_file_name` holds the full `dbfs:/Volumes/...` path; the `_rescued_data` column; the `quality` property; and the source columns of each table from data-model.md. Add one sentence under the intro of the file saying the Silver and Gold sections still describe the earlier pipeline and will be replaced as those layers are rebuilt. Do not edit the Silver and Gold sections
- [X] T023 [P] In `doc/getting-started.md`, rewrite the section `## 3. Create and run the pipeline` to give the commands of contracts/bronze-tables.md (upload with `import-dir`, create from `explorations/setup/03_pipeline_dev.json`, dry run, run, poll), stating that a full refresh is never part of a normal run; and in `## 1. Import the code` replace the reference to `code_tips/` with `src/pipeline/`
- [X] T024 [P] In `doc/README.md`, replace the `code_tips/` entry of the repository layout tree with `src/pipeline/01_bronze/` and its three files with a one-line description each, add `03_pipeline_dev.json` (settings of the development pipeline) under `explorations/setup/`, and update the sentence about numeric prefixes and the "Pipeline datasets" row of the "At a glance" table so they describe what exists now (3 bronze tables)
- [X] T025 Final review against contracts/bronze-tables.md: the three files in `src/pipeline/01_bronze/` match the statement shape and contain nothing from the forbidden list; the copies in the workspace are identical to the repository (upload again if a definition changed after T009); `explorations/setup/03_pipeline_dev.json` matches the pipeline's actual settings; and `git status` shows no change to the setup scripts of features 001 and 002

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies inside this feature; requires features 001 and 002 in place and data in the landing volume
- **Foundational (Phase 2)**: depends on Setup; blocks all user stories
- **User Story 1 (Phase 3)**: depends on Foundational
- **User Story 2 (Phase 4)**: depends on User Story 1, since it inspects the tables that story creates
- **User Story 3 (Phase 5)**: depends on User Story 1; independent of User Story 2
- **Polish (Phase 6)**: depends on all three stories

### User Story Dependencies

- **US1 (P1)**: independent; creates the pipeline and the tables
- **US2 (P1)**: needs US1's tables; adds no code, only proof
- **US3 (P2)**: needs US1's tables; can run before or after US2

The code of all three stories is the same three statements, written once in Phase 2. That
is a deliberate exception to "implement per story", explained under Conventions.

### Within Each User Story

- US1: upload, create, dry run, run, then validate; strictly in order
- US2: the three validations are independent queries and can run in any order
- US3: no-change run, then deliver the file, then run and compare; strictly in order

### Parallel Opportunities

- T002 with T001 (different paths)
- T003, T004 and T005 (three different files)
- T015, T016 and T017 are read-only queries and can run together
- T022, T023 and T024 (three different documentation files)

---

## Parallel Example: Foundational

```bash
# The three definitions are separate files with the same shape:
Task: "Create src/pipeline/01_bronze/dados_api.sql"
Task: "Create src/pipeline/01_bronze/dados_files.sql"
Task: "Create src/pipeline/01_bronze/dados_database.sql"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: run quickstart.md Scenario 1
5. The three bronze tables exist and can be queried; silver work could start

### Incremental Delivery

1. Setup + Foundational → definitions written and reviewed, environment confirmed
2. User Story 1 → pipeline created, tables loaded, counts proven (MVP)
3. User Story 2 → lineage and property proven
4. User Story 3 → incremental behavior proven
5. Polish → documentation describes the bronze layer as built

---

## Notes

- Tasks T007 and T008 only read the workspace. T009 to T012 upload files, create a
  pipeline and create the three tables. T018 and T020 run further updates. T019 writes one
  small file to the landing volume and needs the owner's approval. T021 may run a full
  refresh of one 3-row table and needs the owner's approval.
- The first run ingests about 2.65 million rows, most of them from 8 JSON files; allow a
  few minutes and keep polling the update.
- The pipeline `New Pipeline 2026-08-27 17:09` already in the workspace is not touched. It
  defined the same table names from the deleted `code_tips/` folder and would fail if run
  after this feature. Raise with the owner whether to delete it.
- An empty or missing source folder makes that table's flow fail, by design (research.md,
  Decision 6). T007 guards against it.
- Commit after each phase checkpoint.

## Implementation notes (2026-10-11)

All 25 tasks are complete, run against the `databricks-free` profile chosen by the owner.
The three definitions were not changed after they were first written.

**Pipeline** (T010): `lakeflow_dataslight_dev`, id `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`,
source at `/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline`.

**Row counts after the first run** (T013), each equal to a batch read of its landing folder:

| Table | Rows | Source files |
|---|---|---|
| `dados_api` | 2,550,955 | 8 |
| `dados_files` | 100,000 | 1 |
| `dados_database` | 3 | 1 |

**Findings**:

- **Free Edition serverless quota.** The first two dry runs failed with
  `RESOURCE_EXHAUSTED: You've hit the limit for serverless compute for free usage`. The
  cause was the SQL warehouse, kept running by the validation queries. Stopping it and
  waiting about a minute let the update start. The same was done before each later update.
  This is an environment limit, not a defect of the code; it is now described in
  `doc/getting-started.md`.
- **`source_file_name` has no `dbfs:` scheme.** Inside the pipeline `_metadata.file_path`
  returns `/Volumes/workspace/bronze/landing/...`, while the same expression in a batch
  read on the SQL warehouse returns `dbfs:/Volumes/...`. The first path comparison (T016)
  therefore reported every file as different; with the prefix stripped the two sets are
  identical for all three tables. data-model.md, research.md, quickstart.md and the task
  text were corrected.
- **Refreshing one table.** `databricks pipelines start-update` has only `--full-refresh`
  (all tables). A single table is selected with
  `--json '{"full_refresh_selection": ["dados_database"]}'`.

**Owner's choices** (T019, T021): the test file was uploaded, and the test row was removed
afterwards. The third run added exactly 1 row to `dados_database` (`change_type = update`,
`valor_curso = 147.0`, null `_rescued_data`, later `processing_time`) and nothing to the
other tables. The file was then deleted and `dados_database` alone was fully refreshed: it
is back to 3 rows, and the row counts and latest `processing_time` of `dados_api` and
`dados_files` did not change.

**Not done**: the pipeline `New Pipeline 2026-08-27 17:09` was left untouched, as planned.
