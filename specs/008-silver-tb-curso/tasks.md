---

description: "Task list for feature 008-silver-tb-curso"
---

# Tasks: Silver Course Catalog as the Latest Version of Each Course

**Input**: Design documents from `/specs/008-silver-tb-curso/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/silver-tb-curso.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching step of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Conventions for every task

- **Statement shapes**: exactly those of contracts/silver-tb-curso.md, with a header
  comment in Portuguese in each file.
- **Constitution v1.11.0** is in effect: `vw_bronze_tb_curso` is the course feed's boundary
  view and may convert `valor_curso` to `DECIMAL(9,2)` and add `origem` and `data_carga`,
  and nothing else (Principle I).
- **Never run** `generate_database_data(type_of_data='update row')` or `'delete row'`
  during implementation (spec, Clarifications 2026-10-28). T019 and T020 are the owner's,
  at the talk.
- **Workspace**: `--profile databricks-free` on every command. The pipeline is
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.
- **Free Edition quota**: before each `start-update`:
  1. stop the warehouse (`databricks warehouses stop f796ffb64302b6ba`), but **never while
     queries are still running on it**;
  2. make sure the pipeline is `IDLE`;
  3. wait about 4 minutes after the previous update.
- **Never** refresh an existing table without the owner's explicit approval. If anyone
  starts a full refresh from the UI during implementation, record it and its effects, as
  feature 007 did.
- **Why all definitions are complete before the first run**: changing the columns of an
  `AUTO CDC` target after it has rows needs a refresh of that table.

---

## Phase 1: Setup

- [X] T001 Confirm the starting state, changing nothing:
  - `databricks current-user me --profile databricks-free` succeeds (if the refresh token
    is invalid, **stop and ask the owner** to run `databricks auth login --profile databricks-free`);
  - `.specify/memory/constitution.md` shows version 1.11.0 with the exception "the course
    feed's boundary view";
  - the pipeline is `IDLE`;
  - `02_silver/` in the workspace lists `01_` to `11_` only;
  - `SHOW TABLES IN workspace.silver` does not list `tb_curso`.

---

## Phase 2: Foundational

- [X] T002 Run quickstart.md step 1 and record the result in the Implementation notes. Expected: one change type, `insert`, with 3 rows, 3 courses and `chave_diferente` = 0. If any `update` or `delete` row exists, **stop and ask the owner**: the talk's demo would no longer start from the initial catalog

---

## Phase 3: User Story 1 - One current row per course (Priority: P1) 🎯 MVP

**Goal**: `tb_curso` holds one row per course with its latest values, `origem = 'DATABASE'`,
`data_carga`, and no control or lineage column.

**Independent Test**: quickstart.md step 3. Three rows (`247.00`, `997.00`, `2497.00`),
`linhas` = `cursos` = 3, the six columns of the data model, and every sale and access
joins the catalog.

- [X] T003 [P] [US1] Create `src/pipeline/02_silver/12_vw_bronze_tb_curso.sql` exactly as in the contract: `CREATE TEMPORARY VIEW vw_bronze_tb_curso` selecting `* EXCEPT (source_file_name, _rescued_data, valor_curso)`, `CAST(valor_curso AS DECIMAL(9,2)) AS valor_curso`, `'DATABASE' AS origem` and `current_timestamp() AS data_carga` `FROM STREAM(workspace.bronze.dados_database)`, with no filter. The header comment in Portuguese says this is the course feed's boundary view, that it excludes the two lineage columns, and that it converts the price and adds `origem` and `data_carga` because the `AUTO CDC` flows of `tb_curso` and, later, `dim_curso` cannot compute columns (constitution v1.11.0, Principle I)
- [X] T004 [US1] Create `src/pipeline/02_silver/13_tb_curso.sql` exactly as in the contract:
  - the target `workspace.silver.tb_curso` with `check_curso_uuid` (`curso_uuid IS NOT NULL`), `check_nome_curso` (`nome_curso IS NOT NULL`) and `check_valor_curso` (`valor_curso IS NOT NULL AND valor_curso > 0`), all warn, plus `TBLPROPERTIES ("quality" = "silver")`;
  - `CREATE FLOW silver_tb_curso_flow AS AUTO CDC INTO workspace.silver.tb_curso FROM STREAM(vw_bronze_tb_curso) KEYS (curso_uuid) APPLY AS DELETE WHEN change_type = 'delete' SEQUENCE BY timestamp_change COLUMNS * EXCEPT (change_type, timestamp_change, processing_time) STORED AS SCD TYPE 1`.

  The header comment in Portuguese states SCD type 1, the key, the sequence, the delete condition, that the control columns are dropped by `COLUMNS * EXCEPT`, that there is no hash key (Principle VI exception), and that updates and deletions are shown at the talk.

---

## Phase 4: User Story 2 - Updates overwrite in place (Priority: P1)

**Goal**: an update replaces the course's values in place, ordered by change time.

**Independent Test**: at the talk (T019). During implementation, the definition is
reviewed only.

- [X] T005 [US2] Review `src/pipeline/02_silver/13_tb_curso.sql` for the update behavior: `KEYS (curso_uuid)`, `SEQUENCE BY timestamp_change`, `STORED AS SCD TYPE 1`, no `IGNORE NULL UPDATES`, no `TRACK HISTORY`

---

## Phase 5: User Story 3 - Deletions remove the course (Priority: P1)

**Goal**: a deletion removes the course's row; every other course keeps its latest values.

**Independent Test**: at the talk (T020). During implementation, the definition is
reviewed only.

- [X] T006 [US3] Review `src/pipeline/02_silver/13_tb_curso.sql` for the deletion behavior: `APPLY AS DELETE WHEN change_type = 'delete'` appears **before** `SEQUENCE BY` (Principle V; the parser fails otherwise), and the condition compares the lower-case value `'delete'` that the generator writes

---

## Phase 6: Review and deploy (shared by all stories)

- [X] T007 Review the two files against contracts/silver-tb-curso.md:
  - the view changes no column other than `valor_curso` and adds only `origem` and `data_carga`;
  - no `APPLY CHANGES`, `LIVE`, `CREATE OR REPLACE`, `MERGE`, `md5`, `ON VIOLATION`, `SCD TYPE 2`, `TRACK HISTORY`, `PARTITIONED`, `CLUSTER` or `ai_`;
  - no read of `workspace.bronze` outside `12_vw_bronze_tb_curso.sql`.
- [X] T008 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free`. Confirm that `02_silver/` lists thirteen `FILE`s, and that the two new copies are identical to the repository (export with `--format AUTO` to stdout and `cmp`)
- [X] T009 Following the quota conventions, dry run (`--validate-only`) to `COMPLETED`, with `vw_bronze_tb_curso`, `tb_curso` and `silver_tb_curso_flow` defined. Report any error to the owner
- [X] T010 Following the quota conventions, run the update to `COMPLETED` and record its `update_id` and who created each update in that window (event log `create_update` and `user_action`). If it fails after creating `tb_curso` and a fix changes its columns, **stop and ask the owner** to approve a refresh of `workspace.silver.tb_curso` only

---

## Phase 7: Validation

- [X] T011 [US1] Run quickstart.md step 3:
  - three rows: `beginner` `247.00`, `intermediate` `997.00`, `advanced` `2497.00`, each `origem = 'DATABASE'`;
  - `linhas` = `cursos` = 3, `origem_fora` = `sem_data_carga` = 0;
  - columns: the six of the data model, `valor_curso decimal(9,2)`, none of `change_type`, `timestamp_change`, `processing_time`, `source_file_name`, `_rescued_data`; record their order;
  - `vendas_sem_curso` = `acessos_sem_curso` = 0;
  - `quality` = `silver`.
- [X] T012 Run quickstart.md step 4 for the update that processed the three changes. For dataset `tb_curso`, each of `check_curso_uuid`, `check_nome_curso` and `check_valor_curso` passed 3 and failed 0
- [ ] T013 Ask the owner to confirm that the Data quality tab of `tb_curso` shows the three expectations. Record the answer

---

## Phase 8: Polish

- [X] T014 Following the quota conventions, run an update with no new data, unless T010's window already contains one that ran after the load. Confirm that `silver_tb_curso_flow` applies 0 changes and T011's results are unchanged
- [X] T015 [P] In `doc/pipeline-reference.md`:
  - rewrite `### tb_curso` as built: source `vw_bronze_tb_curso`, key `curso_uuid`, sequence `timestamp_change`, delete condition `change_type = 'delete'`, SCD type 1, `COLUMNS * EXCEPT (change_type, timestamp_change, processing_time)`, the six columns with `valor_curso DECIMAL(9,2)`, the three expectations, and that updates and deletions are shown at the talk;
  - in `### Temporary views`, replace the `vw_bronze_tb_curso` row with the built view, linked to `12_`, stating it is the course feed's boundary view under constitution v1.11.0;
  - add both to the intro's "as built" list.
- [X] T016 [P] In `doc/architecture.md`, point the features-table row "`AUTO CDC` as SCD type 1" to `../src/pipeline/02_silver/13_tb_curso.sql`
- [X] T017 [P] In `doc/README.md`, add `12_vw_bronze_tb_curso.sql` and `13_tb_curso.sql` to the `02_silver/` layout, and change the dataset count to: in silver, 7 streaming views, 1 private streaming table and 5 streaming tables
- [X] T018 [P] In `doc/known-issues.md`, replace the smaller item "`dim_curso` and `tb_curso` both read the bronze change feed. `tb_curso` is not consumed by any gold table." with a statement that both read the feed through `vw_bronze_tb_curso` by design (constitution Principle I), and that `tb_curso` is the silver reference for sales and accesses
- [X] T019 Final review:
  - the workspace copies are identical to the repository;
  - `git status` shows changes only in `src/pipeline/02_silver/`, `doc/` and `specs/008-silver-tb-curso/`;
  - the files of features 004–007 are unchanged;
  - `bronze.dados_database` still holds only the three inserts.

  Complete the Implementation notes.

---

## Phase 9: At the talk (owner)

- [ ] T020 [US2] At the talk, the owner runs `generate_database_data(type_of_data='update row')` and a pipeline update. Expected (quickstart.md step 6): 3 rows; the beginner course at `147.00` with a new `data_carga`; no row at `247.00`
- [ ] T021 [US3] At the talk, after T020, the owner runs `generate_database_data(type_of_data='delete row')` and a pipeline update. Expected: 2 rows; no beginner course; the other two unchanged

---

## Dependencies & Execution Order

- Setup (T001) → Foundational (T002) → definitions (US1 T003–T004) → reviews (US2 T005,
  US3 T006, T007) → deploy (T008–T010) → validation (T011–T013) → Polish (T014–T019) →
  the talk (T020 → T021).
- T002 blocks everything: if the catalog is no longer in its initial state, the owner
  decides before any file is written.
- All three stories share `13_tb_curso.sql`. US1 is built and validated during
  implementation; US2 and US3 are reviewed during implementation and validated at the talk.
- Parallel: T003 (the view) can be written alongside the start of T004; T015, T016, T017
  and T018 (separate docs).

## Parallel Example

```text
After T002:
  T003 [US1] 12_vw_bronze_tb_curso.sql
then T004 (13_tb_curso.sql), T005, T006, T007.

After T014:
  T015 pipeline-reference.md | T016 architecture.md | T017 README.md | T018 known-issues.md
```

## Implementation Strategy

One deploy, because each Free Edition update costs a quota cycle. MVP = US1 validated
(T011). US2 and US3 are complete in code after T005–T006 and proven at the talk (T020–T021),
as the owner chose.

## Implementation notes

### 2026-10-28

**T001**: login valid (`arthur.luz@dataslight.com.br`); constitution v1.11.0 with the
exception "the course feed's boundary view"; pipeline `IDLE` (last updates `8954b177` and
`c52cd902`, both `COMPLETED`); `02_silver/` held `01_`–`11_`; `workspace.silver` held
`tb_acesso`, `tb_quarentena`, `tb_usuario`, `tb_venda`, no `tb_curso`.

**T002**: `bronze.dados_database` holds one change type, `insert`: 3 rows, 3 courses,
`chave_diferente` 0. The landing folder `database/` holds one data file (plus Spark's
marker files, which Auto Loader skips). No update or delete row: the catalog is in its
initial state for the talk.

**T003–T007**: two files written. `13_tb_curso.sql` has `KEYS (curso_uuid)`,
`SEQUENCE BY timestamp_change` and `STORED AS SCD TYPE 1`, with no `IGNORE NULL UPDATES`
or `TRACK HISTORY` (T005); the delete condition is on line 24, before `SEQUENCE BY` on line
25 (T006). No forbidden token; only `12_` reads `workspace.bronze` (T007).

**T008**: upload complete; `02_silver/` lists thirteen `FILE`s; both new copies are
identical to the repository. Warehouse stopped.

**T009**: dry run `0de0f129-3879-4717-90d6-0c882a8e7c6f` **COMPLETED**, no error event;
`vw_bronze_tb_curso`, `workspace.silver.tb_curso` and the flow are defined. The flow
appears as `workspace.bronze.silver_tb_curso_flow` (open flow-name finding).

**T010**: update `746a6970-9322-4abd-936b-52657d37df16` **COMPLETED**. In the window only
this task's two updates were created, both `API_CALL`, neither a full refresh: the dry run
`0de0f129` (21:43:39 UTC) and this update (21:48:55).

**T011**: three rows, ordered by price: `beginner` *Construindo um Data Lakehouse com SQL
e DLT* 247.00, `intermediate` *Mastering SQL no Databricks* 997.00, `advanced` *Programa
Data Heroes* 2497.00, each `origem = 'DATABASE'`, `data_carga` 2026-10-28T21:50:33.586Z.
`linhas` = `cursos` = 3; `origem_fora` = `sem_data_carga` = 0. Columns, in order:
`curso_uuid string, nome_curso string, nivel_curso string, valor_curso decimal(9,2),
origem string, data_carga timestamp`; no control or lineage column. `vendas_sem_curso` =
`acessos_sem_curso` = 0. `quality` = `silver`.

**T012**: in update `746a6970`, `check_curso_uuid`, `check_nome_curso` and
`check_valor_curso` each passed 3, failed 0. The flow's events carry no
`num_output_rows` metric for an `AUTO CDC` flow; the table's contents (T011) are the
evidence of the three applied changes.

**T013**: open, for the owner.

**T014**: update `3c52c735-a49b-4eb9-bba4-f657d4855689` (no new data, `API_CALL`, no full
refresh) **COMPLETED**. `tb_curso` still has 3 rows and the same `data_carga`
(21:50:33.586Z), so the flow applied no change.

**T015–T018**: `doc/pipeline-reference.md` (`### tb_curso` as built; the
`vw_bronze_tb_curso` row; the intro), `doc/architecture.md` (features row to
`13_tb_curso.sql`), `doc/README.md` (layout `12_`–`13_`; silver 7 streaming views, 1
private streaming table, 5 streaming tables) and `doc/known-issues.md` (the
`dim_curso`/`tb_curso` item restated as the intended design).

**T019**: all thirteen `02_silver` workspace files are identical to the repository.
`bronze.dados_database` still holds only the three inserts. The owner committed the work
during implementation (`d80ecc3`, `7d34289`, `ceb7bfb`); every file in those commits is in
`src/pipeline/02_silver/`, `doc/` or `specs/008-silver-tb-curso/`, plus the v1.11.0
amendment in `.specify/memory/constitution.md`. Features 004–007's files are unchanged.

**Open (owner)**:
- T013: the Data quality tab of `tb_curso`.
- T020–T021: the update and the deletion, at the talk (quickstart.md step 6).
- The flow-name finding (now five flows under `workspace.bronze`).
- Remove the constitution's Sync Impact Report (committed in `d80ecc3`).
