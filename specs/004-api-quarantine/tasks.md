---

description: "Task list for feature 004-api-quarantine (revised for constitution v1.6.0)"
---

# Tasks: Validation and Quarantine of API Events

**Input**: Design documents from `/specs/004-api-quarantine/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/silver-validation-quarantine.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching step of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Revision (2026-10-18)**: regenerated after the owner amended the constitution to v1.6.0.
The amendment added numbered files per zone, a boundary view before each zone change, and
streaming-only bronze and silver, and removed the rescued-data rule. Tasks already done
under the first list are kept as done where they still hold. The previous IDs are in the
Implementation notes, which are preserved below.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pipeline SQL (project code): `src/pipeline/01_bronze/` and `src/pipeline/02_silver/`
- Documentation: `doc/`
- All paths below are relative to the repository root

## Conventions for every task

- **The three rules**, fixed by data-model.md. They appear twice in the validation file:
  once as `CONSTRAINT` clauses, once as `CASE` lines. Both lists use this text and this
  order, character for character:

  | Order | Name | Condition (passes when true) |
  |---|---|---|
  | 1 | `curso_invalido` | `payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` |
  | 2 | `valor_invalido` | `payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00'` |
  | 3 | `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----'` |

  The placeholder in rule 1 is exactly 32 lowercase `x`.

- **Boundary view shape**: one short header comment in Portuguese, then exactly:

  ```sql
  CREATE TEMPORARY VIEW vw_bronze_dados_api
  COMMENT '<description in Portuguese>'
  AS
  SELECT
    * EXCEPT (source_file_name, _rescued_data)
  FROM STREAM(workspace.bronze.dados_api);
  ```

- **Validation statement shape**: one short header comment in Portuguese, then exactly:

  ```sql
  CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api (
    CONSTRAINT curso_invalido           EXPECT (<rule 1>),
    CONSTRAINT valor_invalido           EXPECT (<rule 2>),
    CONSTRAINT forma_pagamento_invalido EXPECT (<rule 3>)
  )
  PARTITIONED BY (fl_registro_invalido)
  COMMENT '<description in Portuguese>'
  TBLPROPERTIES ("quality" = "silver")
  AS
  SELECT
    *,
    filter(
      array(
        CASE WHEN NOT (<rule 1>) THEN 'curso_invalido' END,
        CASE WHEN NOT (<rule 2>) THEN 'valor_invalido' END,
        CASE WHEN NOT (<rule 3>) THEN 'forma_pagamento_invalido' END
      ),
      r -> r IS NOT NULL
    ) AS regras_violadas,
    size(regras_violadas) > 0 AS fl_registro_invalido,
    'API' AS origem,
    current_timestamp() AS data_carga
  FROM STREAM(vw_bronze_dados_api);
  ```

- **Quarantine statement shape**: one short header comment in Portuguese, then exactly:

  ```sql
  CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_quarentena (
    CONSTRAINT regra_violada_registrada EXPECT (size(regras_violadas) > 0)
  )
  COMMENT '<description in Portuguese>'
  TBLPROPERTIES ("quality" = "silver")
  AS
  SELECT
    *,
    current_timestamp() AS data_carga_quarentena
  FROM STREAM(workspace.silver.temp_tb_validacao_api)
  WHERE fl_registro_invalido;
  ```

- **Forbidden**: see the contract's list. In short:
  - `source_file_name` or `_rescued_data` in a silver table;
  - a read of bronze other than in the view;
  - anything in the view beyond excluding those two columns;
  - `ON VIOLATION`;
  - `CLUSTER BY`;
  - `PARTITIONED BY` outside the validation table;
  - a materialized view;
  - `CAST` or renames of delivered columns;
  - `DISTINCT`, `GROUP BY`, joins, or a `WHERE` in the view or the validation table;
  - `CREATE FLOW`, `LIVE`, `CREATE OR REPLACE`, `APPLY CHANGES`;
  - a catalog other than `workspace`;
  - a file without its `NN_` prefix.
- **Allowed fallback, and only this one**: if the lateral alias `size(regras_violadas)` is
  rejected, build `regras_violadas` in a subquery in the `FROM` clause over
  `STREAM(vw_bronze_dados_api)`. Then derive the flag, `origem` and `data_carga` in the
  outer `SELECT`. Report anything else to the owner.
- **Running against the workspace**: the owner's profile is `databricks-free`; pass
  `--profile databricks-free` every time. The pipeline is `lakeflow_dataslight_dev`, id
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.
- **SQL queries**: `databricks experimental aitools tools query "<sql>" --profile
  databricks-free --output csv`. Record every number the tasks ask for in the
  Implementation notes.
- **Free Edition quota**: SQL queries wake the SQL warehouse, which counts against the
  same serverless quota as the pipeline. Before every `start-update`:
  1. stop the warehouse (`databricks warehouses stop f796ffb64302b6ba --profile databricks-free`);
  2. make sure no update of the owner's is running;
  3. wait about 4 minutes after the previous update ended.

  A start that fails within seconds with `RESOURCE_EXHAUSTED` is the quota, not the code.
- **Polling**: after `start-update`, poll `databricks pipelines get-update <pipeline_id>
  <update_id> --profile databricks-free` and read `.update.state` until `COMPLETED`, `FAILED`
  or `CANCELED`. On `FAILED`, read the `ERROR` events from `databricks pipelines
  list-pipeline-events` and fix the cause. Do not simply run again.
- **Never** pass `--full-refresh` or `full_refresh_selection` without the owner's explicit
  approval for that run.
- **Event log queries** are those of quickstart.md step 4.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: folders, numbering and the pipeline to extend

- [X] T001 Create the folder `src/pipeline/02_silver/`
- [X] T002 Confirm the pipeline with `databricks pipelines get 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free`: name `lakeflow_dataslight_dev`, catalog `workspace`, serverless, development, single glob `/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline/**`. `explorations/setup/03_pipeline_dev.json` is not changed by this feature
- [X] T003 Rename the bronze files with `git mv`, content unchanged: `src/pipeline/01_bronze/dados_api.sql` → `src/pipeline/01_bronze/01_dados_api.sql`, `dados_files.sql` → `02_dados_files.sql`, `dados_database.sql` → `03_dados_database.sql`. `git diff --cached -M --stat` must show pure renames

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the facts every story depends on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] Read the `databricks-pipelines` skill: `SKILL.md`, `references/streaming-table-sql.md`, `references/expectations-sql.md`, `references/temporary-view-sql.md`. Note any disagreement with contracts/silver-validation-quarantine.md
- [X] T005 [P] Confirm the bronze columns of `workspace.bronze.dados_api` (`processing_time`, `source_file_name`, `access_date`, `access_point`, `ip_address`, `payload`, `_rescued_data`), and the types of the three rule fields. `payload.info_pagamento.valor` is `DOUBLE`
- [X] T006 Re-run the expected-counts query of quickstart.md step 1 (three rules) on `workspace.bronze.dados_api`, because the owner fully refreshed bronze on 2026-10-18 after the first count. Record `total`, the three rule counts and `invalidos`. If any rule count is 0, stop and report. Then stop the SQL warehouse (Conventions)
- [X] T007 [P] Confirm that no published silver table exists yet (`SHOW TABLES IN workspace.silver` returns no rows). The private table's empty backing table from the first attempt is expected and is handled in T015

**Checkpoint**: the rules are known to catch real rows, and the target names are free

---

## Phase 3: User Story 1 - Mark every API event as valid or invalid (Priority: P1) 🎯 MVP

**Goal**: the boundary view delivers every bronze API event without `source_file_name` and `_rescued_data`. The private validation table holds every one of them, unchanged, with `regras_violadas` and a never-null `fl_registro_invalido`, partitioned by the flag.

**Independent Test**: after the update of T015, the event log shows that the validation flow wrote exactly `total` rows (T006), and the update accepted the view and the private, partitioned, three-level definition. The table is private, so its flag values are proven through the expectations (US2) and the quarantine table (US3).

### Implementation for User Story 1

- [X] T008 [US1] Create `src/pipeline/02_silver/01_vw_bronze_dados_api.sql` in the boundary view shape of the Conventions. Use `COMMENT 'Eventos da API vindos do bronze, sem source_file_name e _rescued_data.'`, and a header comment in Portuguese saying that the view is the bronze-to-silver boundary of the API source, that it removes the bronze-only lineage columns, and that it applies no filter, conversion or rule
- [X] T009 [US1] Create `src/pipeline/02_silver/02_temp_tb_validacao_api.sql` in the validation statement shape of the Conventions, with the three rules substituted verbatim. It replaces the first version, `src/pipeline/02_silver/temp_tb_validacao_api.sql`. Use `COMMENT 'Eventos da API validados: cada evento da view de fronteira, sem alteração, com as regras violadas e a flag fl_registro_invalido.'`. Column rules from data-model.md:
  - `regras_violadas`: "empty array when none failed; never `NULL`";
  - `fl_registro_invalido`: "never `NULL`";
  - `origem`: "literal `'API'`… not derived from the data";
  - `data_carga`: "`current_timestamp()`… never `NULL`".
- [X] T010 [US1] Review `src/pipeline/02_silver/01_vw_bronze_dados_api.sql` and `src/pipeline/02_silver/02_temp_tb_validacao_api.sql` against the contract:
  - the view's select list is only `* EXCEPT (source_file_name, _rescued_data)` over `STREAM(workspace.bronze.dados_api)`;
  - the validation table is `PRIVATE`, three-level named, reads `STREAM(vw_bronze_dados_api)`, and has `PARTITIONED BY (fl_registro_invalido)` and `TBLPROPERTIES ("quality" = "silver")`;
  - the three `CONSTRAINT` conditions equal the three `CASE WHEN NOT (...)` conditions character for character, in the same order;
  - no file contains `ON VIOLATION`, `CLUSTER BY`, `MATERIALIZED VIEW`, `LIVE`, or a `WHERE`.

**Checkpoint**: the split point is written; it is deployed together with US3 in Phase 5

---

## Phase 4: User Story 3 - Keep invalid events in a quarantine table (Priority: P1), definition

**Goal**: the quarantine definition exists, so that a single update creates the view, the validation table and the quarantine table. This saves one update cycle against the Free Edition quota.

### Implementation for User Story 3 (definition)

- [X] T011 [US3] Create `src/pipeline/02_silver/03_tb_quarentena.sql` in the quarantine statement shape of the Conventions. Use `COMMENT 'Quarentena dos eventos da API rejeitados pela validação, sem alteração, com as regras violadas.'`. Add a header comment in Portuguese saying that the table receives the rows of `temp_tb_validacao_api` with `fl_registro_invalido = true`, keeps the event as delivered by the boundary view so that it can be inspected and reprocessed, and records the rules in `regras_violadas`. Column rules from data-model.md:
  - every column of the view keeps the "same name, type and value";
  - `regras_violadas` holds "at least one name";
  - `origem` is `'API'`;
  - every validation column is kept, with nothing excluded or replaced (FR-012a): `regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga` (validation time);
  - `data_carga_quarentena` is "when the row entered quarantine; never `NULL`".
  - Revised 2026-10-18: the first version dropped the flag and replaced `data_carga`. The owner then added the constitution rule that quarantine keeps every field.
- [X] T012 [US3] Review `src/pipeline/02_silver/03_tb_quarentena.sql` against the contract:
  - it is a published (not `PRIVATE`) streaming table, three-level named, with `TBLPROPERTIES ("quality" = "silver")` and the single warn expectation `regra_violada_registrada`;
  - it reads only `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE fl_registro_invalido`;
  - its select list is `*` followed by `current_timestamp() AS data_carga_quarentena`, with no `EXCEPT`;
  - it has no layout clause and nothing from the forbidden list.

---

## Phase 5: Deploy (shared by all stories)

**Purpose**: one upload, one dry run and one real update for all silver files and the bronze renames

- [X] T013 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free`. Then delete the unnumbered files left in the workspace with `databricks workspace delete` on each path: `.../01_bronze/dados_api.sql`, `.../01_bronze/dados_files.sql`, `.../01_bronze/dados_database.sql`, `.../02_silver/temp_tb_validacao_api.sql`. Confirm with `databricks workspace list` that `01_bronze` holds exactly `01_dados_api.sql`, `02_dados_files.sql`, `03_dados_database.sql`, and `02_silver` holds exactly `01_vw_bronze_dados_api.sql`, `02_temp_tb_validacao_api.sql`, `03_tb_quarentena.sql`, all as `FILE`
- [X] T014 Following the quota conventions, run a dry run with `databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --validate-only --profile databricks-free` and poll it. It must be `COMPLETED`, with events defining `vw_bronze_dados_api`, `temp_tb_validacao_api` and `tb_quarentena`, and each bronze table defined once. On the lateral-alias error, apply the allowed fallback in `src/pipeline/02_silver/02_temp_tb_validacao_api.sql`, re-upload and repeat. Report any other error
- [X] T015 Following the quota conventions, run the real update with `databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free`, poll it to a terminal state and record its `update_id`. If it fails because the empty backing table of `temp_tb_validacao_api` has the old schema, **stop and ask the owner** to approve a refresh of that table only (`--json '{"full_refresh_selection": ["workspace.silver.temp_tb_validacao_api"]}'`). It holds no rows (research.md Decision 8). On `COMPLETED`, confirm that `SHOW TABLES IN workspace.silver` lists `tb_quarentena` and not `temp_tb_validacao_api`

**Checkpoint**: all silver datasets are created and filled

---

## Phase 6: User Story 1 - validation

- [X] T016 [US1] With the first event log query of quickstart.md step 4 for the update of T015, confirm that the flow of `temp_tb_validacao_api` wrote exactly `total` rows (T006), so no event was dropped (FR-002, SC-001). Record the number

---

## Phase 7: User Story 2 - Count every rule violation in the pipeline's quality metrics (Priority: P1)

**Goal**: the three rules appear by name in the pipeline's data quality metrics, with failed counts equal to what bronze predicts, and no row is dropped.

**Independent Test**: quickstart.md step 4, expectations query. For `temp_tb_validacao_api`, the three names are listed, each `falhou` equals its count from T006, and `passou + falhou = total` for each rule.

### Implementation for User Story 2

- [X] T017 [US2] Run the expectations query of quickstart.md step 4 for the update of T015. Confirm:
  - dataset `temp_tb_validacao_api` lists exactly `curso_invalido`, `valor_invalido` and `forma_pagamento_invalido`;
  - each rule's `falhou` equals its count from T006;
  - `passou + falhou = total` for each rule.

  Record the three `falhou` values. A mismatch means a `CONSTRAINT` and its `CASE` line differ: report it to the owner before fixing.
- [ ] T018 [US2] Confirm that the rules only measure: the update of T015 is `COMPLETED`; `grep -n "ON VIOLATION" src/pipeline/02_silver/*.sql` returns nothing; and T016's count equals `total`. Ask the owner to confirm, in the pipeline UI, that the Data quality tab of `temp_tb_validacao_api` shows the three expectations with their metrics (completion gate 2). Record the answer

---

## Phase 8: User Story 3 - Keep invalid events in a quarantine table (Priority: P1), validation

**Goal**: `workspace.silver.tb_quarentena` holds exactly the flagged events, as delivered by the boundary view, with every column of the validation table (rules, flag, `origem = 'API'`, validation `data_carga`) plus `data_carga_quarentena`.

**Independent Test**: quickstart.md step 3. The quarantine count equals `invalidos` (T006), the per-rule counts equal T006's, both `EXCEPT ALL` sides return 0, the column list is every validation column plus `data_carga_quarentena` with no bronze-only column, and no row lacks `origem`, `data_carga`, `data_carga_quarentena` or a rule name.

### Implementation for User Story 3 (validation)

- [X] T019 [P] [US3] Run the two count queries of quickstart.md step 3 on `workspace.silver.tb_quarentena`. Confirm that the total equals `invalidos` (T006), and that each rule's count from `explode(regras_violadas)` equals its count from T006 and its `falhou` from T017. Record the counts
- [X] T020 [P] [US3] Run the remaining queries of quickstart.md step 3:
  - the checks return `origem_errada = 0`, `sem_data_carga = 0`, `sem_data_carga_quarentena = 0`, `flag_falsa = 0` and `sem_regra = 0`;
  - the `information_schema.columns` query lists exactly the ten columns of quickstart.md step 3, with no `source_file_name` or `_rescued_data`;
  - both `EXCEPT ALL` sides return 0 (FR-010, SC-005).

  Also confirm `SHOW TBLPROPERTIES workspace.silver.tb_quarentena ('quality')` is `silver`.
- [X] T021 [P] [US3] Run the expectations query of quickstart.md step 4 for the update of T015. Confirm that dataset `tb_quarentena` lists `regra_violada_registrada` with `falhou = 0` and `passou = invalidos`

**Checkpoint**: invalid events are preserved with their reasons; nothing is silently discarded

---

## Phase 9: User Story 4 - Let valid events continue downstream (Priority: P2)

**Goal**: valid and quarantined events partition bronze exactly, and later runs process only new events.

**Independent Test**: bronze `total` = (`total` − `invalidos`) valid + quarantine count, with a difference of 0. A run with no new bronze rows adds 0 rows to both tables.

### Implementation for User Story 4

- [X] T022 [US4] Reconcile (FR-013, SC-004). Compute valid = validation rows (T016) − quarantine rows (T019). Confirm that valid = `total` − `invalidos`, and that bronze `total` = valid + quarantined with a difference of 0. Record the three numbers
- [X] T023 [US4] Prove incremental behavior (FR-015, SC-007). Following the quota conventions, run another update with no new landing data and poll it to `COMPLETED`. With the first event log query of quickstart.md step 4 for this update, confirm that the `temp_tb_validacao_api` and `tb_quarentena` flows each wrote 0 rows, and that the quarantine count is unchanged

**Checkpoint**: the split is exact and incremental; the valid side is ready for the conformed tables of later features

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: the documentation required by FR-018 (and US4 scenario 3 for the consumer rule), and the final review

- [X] T024 [P] In `doc/pipeline-reference.md`:
  - Rename the bronze file links to `01_dados_api.sql`, `02_dados_files.sql` and `03_dados_database.sql`.
  - In `### Temporary views`, replace the `vw_bronze_dados_api` row with the new view: file `src/pipeline/02_silver/01_vw_bronze_dados_api.sql`; `bronze.dados_api` minus `source_file_name` and `_rescued_data`; a streaming temporary view.
  - Rewrite `### temp_tb_validacao_api`. Cover:
    - the file `src/pipeline/02_silver/02_temp_tb_validacao_api.sql`;
    - that it is a private streaming table, partitioned by `fl_registro_invalido` (a recorded exception to Principle V, because liquid clustering rejects `BOOLEAN` columns), reading `vw_bronze_dados_api`;
    - the table of the three rules, with conditions and "empty field passes";
    - the columns `regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga`;
    - that the expectations only measure;
    - the consumer rule: conformed tables read `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE NOT fl_registro_invalido`, and do not restate the rules.
  - Rewrite `### tb_quarentena`. Cover:
    - the file `src/pipeline/02_silver/03_tb_quarentena.sql`;
    - the flagged rows, as delivered by the view;
    - every column of the validation table (constitution Principle IV), plus `data_carga_quarentena`;
    - the expectation `regra_violada_registrada`;
    - that it has no hash key, because it is not conformed.
  - Add a reconciliation line: bronze `dados_api` = valid + quarantined.
  - Change the intro so it says that the bronze section and these silver sections describe the pipeline as built, while the other silver sections and gold still describe the earlier pipeline.
- [X] T025 [P] In `doc/architecture.md`:
  - Keep the graph edge `L1 --> B1 --> V1 --> T1`.
  - In the "Lakeflow features demonstrated" table, point these rows to the new files:
    - "Temporary streaming views" → `../src/pipeline/02_silver/01_vw_bronze_dados_api.sql`, keeping the other `vw_` links;
    - "Temporary (pipeline-private) streaming table" and "Expectations that only record violations" → `02_temp_tb_validacao_api.sql`;
    - "Quarantine pattern (flag column + split)" → `02_temp_tb_validacao_api.sql` and `03_tb_quarentena.sql`.
  - Add a row "Partitioning by a Boolean flag (`PARTITIONED BY`; `CLUSTER BY` rejects `BOOLEAN`)" → `02_temp_tb_validacao_api.sql`.
  - Rename any bronze file links to the numbered names.
- [X] T026 [P] In `doc/README.md`, update the repository layout so that `src/pipeline/01_bronze/` lists `01_dados_api.sql`, `02_dados_files.sql` and `03_dados_database.sql`, and `src/pipeline/02_silver/` lists its three files with a one-line description each. Update the "Pipeline datasets" row of the "At a glance" table to what exists now: 3 bronze tables, 1 silver view, 1 private silver table and 1 silver table
- [X] T027 [P] In `doc/known-issues.md`, delete the table row for `04_tb_quarentena.sql:4` under `## Catalog name mismatch`, and the paragraph beginning "The quarantine table is the one that matters for the pipeline". Keep the other rows
- [X] T028 Final review against contracts/silver-validation-quarantine.md:
  - the files in `src/pipeline/01_bronze/` and `src/pipeline/02_silver/` match their shapes and the numbering;
  - the workspace copies are identical to the repository, and no unnumbered file remains in the workspace;
  - `git status` shows changes only in `src/pipeline/`, `doc/`, `specs/004-api-quarantine/` and `.specify/memory/constitution.md`;
  - `explorations/setup/03_pipeline_dev.json` is unchanged.

  Then complete the Implementation notes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** and **Foundational (Phase 2)**: block everything
- **US1 definition (Phase 3)** and **US3 definition (Phase 4)**: after Foundational; T011 needs no US1 result, only the contract
- **Deploy (Phase 5)**: after Phases 3 and 4
- **US1 validation (Phase 6)**, **US2 (Phase 7)**, **US3 validation (Phase 8)**: after Deploy. T019 compares with T017, so run Phase 7 first if possible
- **US4 (Phase 9)**: after Phases 6 and 8
- **Polish (Phase 10)**: after all stories

### Why one deploy for all stories

Each update on Free Edition costs a wait of about 4 minutes for the serverless quota. The
first task list deployed US1 and US3 separately. Its notes allowed deploying them together,
and the owner's deployment attempts showed how costly each cycle is. One update now
creates the view and both tables. Each story is still validated on its own.

### Parallel Opportunities

- T004, T005 and T007 are independent reads
- T011 can be written while T010 is reviewed
- T019, T020 and T021 are read-only queries
- T024–T027 edit four different documentation files

---

## Parallel Example: User Story 3 validation

```bash
Task: "Quarantine counts per rule vs T006 and T017 (T019)"
Task: "origem / data_carga / regras_violadas checks, absent columns, EXCEPT ALL, properties (T020)"
Task: "regra_violada_registrada expectation metrics (T021)"
```

## Parallel Example: Polish

```bash
Task: "Rewrite bronze links and the silver sections of doc/pipeline-reference.md (T024)"
Task: "Update the feature table of doc/architecture.md (T025)"
Task: "Update the layout in doc/README.md (T026)"
Task: "Remove the resolved quarantine entry from doc/known-issues.md (T027)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Setup + Foundational
2. US1 definition, then deploy only the view and the validation table (move `03_tb_quarentena.sql` aside before T013)
3. **STOP and VALIDATE** with T016

The chosen path deploys everything at once (Phase 5), because each extra update costs a
quota cycle.

### Incremental Delivery

1. Setup + Foundational → facts recorded
2. US1 + US3 definitions → three files written and reviewed
3. Deploy → one update creates all silver datasets
4. US1, US2, US3 validations → split, metrics and quarantine proven
5. US4 → reconciliation and incremental behavior proven
6. Polish → documentation describes the pipeline as built

---

## Notes

- What touches the workspace:
  - T006 and T016–T022 only read.
  - T013 uploads files and deletes the four obsolete workspace copies.
  - T014, T015 and T023 run pipeline updates. A refresh happens only with the owner's approval (T015).
- Earlier IDs, for reading the notes below:

  | Earlier ID | Now |
  |---|---|
  | T001, T002 | T001, T002 |
  | T003–T006 | T004, T005, T006, T007 |
  | T007, T008 | T008–T010 |
  | T009–T011 | T013–T015 |
  | T012–T014 | T016–T018 |
  | T015, T016 | T011, T012 |
  | T017–T021 | T013–T015, T019–T021 |
  | T022, T023 | T022, T023 |
  | T024–T027 | T024–T028 |

- Commit after each phase checkpoint.

## Implementation notes

### 2026-10-18, first session

**Profile**: the owner chose `DEFAULT` (`https://dbc-7e0f02e0-ff06.cloud.databricks.com`,
the same workspace as feature 003). Its personal access token is accepted for SQL
statements and workspace files. It is refused for the pipelines API and the Unity Catalog
API (`Provided access token does not have required scopes: pipelines` /
`unity-catalog`). The profile `databricks-free` is marked invalid by
`databricks auth profiles`. **T002 and every task that runs or inspects the pipeline are
blocked until the owner gives a profile with those scopes.**

**Profile change**: the owner re-authenticated `databricks-free` (OAuth, same workspace)
and asked to deploy. From T002 on, every command uses `databricks-free`.

**T002**: `lakeflow_dataslight_dev` (`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`) matches:
catalog `workspace`, serverless, development, single glob over `src/pipeline/**`. Its
latest update before this feature, `68a80a60-...`, completed at 14:30 UTC, after two
failed ones at 14:26.

**T009**: `src/pipeline` uploaded; `02_silver/temp_tb_validacao_api.sql` is a `FILE`.

**T010**: the dry run started by the CLI (`25ff37aa-...`, 14:32 UTC) failed on the Free
Edition quota (`RESOURCE_EXHAUSTED: You've hit the limit for serverless compute for free
usage`), with the SQL warehouse already stopped and no other pipeline, app or job
running. The owner then ran a validation from the UI (`a142e0e5-...`, 14:34 UTC), which
**completed**. It defined `workspace.silver.temp_tb_validacao_api` as a streaming table
and its append flow, so the qualified private name and the lateral alias were accepted.
No fallback was needed. A validate-only run does not create tables, so it could not catch
the layout error below. A later UI start
(`69431660-...`, 14:35) failed on the same quota.

**Quota pattern**: every failed update today (8 of them) failed within about 2 seconds
with the same quota error. Each time, the next success came several minutes after the
previous update finished. Free Edition seems to keep serverless capacity reserved for a
few minutes after an update. Waiting about 4 minutes before starting works; retrying
sooner does not.

**Bronze was fully refreshed by the owner today** (updates `db0a7100-...` 13:46 and
`d6819922-...` 13:56 UTC reset all three bronze tables). The T005 counts are re-checked
before they are compared with the silver results.

**T003**: skill read (`SKILL.md`, `references/streaming-table-sql.md`,
`references/expectations-sql.md`). No disagreement with the contract. The skill lists
`CLUSTER BY` and `PRIVATE` in the same streaming table syntax and prefers `CLUSTER BY`.

**T004**: bronze columns as expected. Types: `payload.info_pagamento.valor` **DOUBLE**,
`payload.info_produto.product_name` STRING, `payload.info_pagamento.forma_pagamento`
STRING. Rule 2 therefore compares numbers: every zero amount is rejected (research.md
Decision 4).

**T005**, expected counts on `workspace.bronze.dados_api`:

| total | curso_invalido | valor_invalido | forma_pagamento_invalido | registro_nao_conforme | invalidos |
|---|---|---|---|---|---|
| 2,550,955 | 9,240 | 9,240 | 6,934 | 0 | 9,240 |

The rules overlap completely: every event with the placeholder course has a zero payment
value, and the `'-----'` payment method appears only on those events.

**T006**: checked with `SHOW TABLES IN workspace.silver` on the SQL warehouse, because
`databricks tables list` needs the Unity Catalog scope. The schema is empty.

**T008**: the four `CONSTRAINT` conditions and the four `CASE` conditions were compared
mechanically and are identical; no forbidden token. As an extra check, the file's `SELECT`
was run as a batch query over bronze on the SQL warehouse. The lateral alias
`size(regras_violadas)` resolved, and the result matches T005:

| regras_violadas | fl_registro_invalido | rows |
|---|---|---|
| (empty) | false | 2,541,715 |
| curso_invalido, valor_invalido, forma_pagamento_invalido | true | 6,934 |
| curso_invalido, valor_invalido | true | 2,306 |

**Layout change (T011)**: the first real updates, the owner's `44f61719-...` (14:39 UTC)
and the CLI's `b22b266c-...` (14:41 UTC), failed in `SETTING_UP_TABLES` with
`[DELTA_CLUSTERING_COLUMNS_DATATYPE_NOT_SUPPORTED] CLUSTER BY is not supported because the
following column(s): fl_registro_invalido : BOOLEAN don't support data skipping.`
`44f61719` had already created the private table's backing table,
`workspace.silver.__8d51ac7a_02be_4ce2_8afd_f4f263e448dd_temp_tb_validacao_api`, with no
rows. The owner decided to partition instead, as the original request said. The file now
has `PARTITIONED BY (fl_registro_invalido)`. The spec (FR-008, User Story 1 scenario 8,
Assumptions), plan (Principle V deviation and Complexity Tracking), research Decision 2,
data model, contract, quickstart and this file were updated to match. The workspace copy
was re-uploaded and is identical to the repository.

### 2026-10-18, rework for constitution v1.6.0

**Update `7c69f3e9-...` (14:46 UTC)** was started by the CLI with the partitioned v1.5.0
definition and was stopped by the CLI at 14:46:27. The owner was about to amend the
constitution, and the run would have written 2.55 million rows with `source_file_name` and
`_rescued_data`. It ended `CANCELED`. The silver flow was `SKIPPED`, so no row was written.
It passed `SETTING_UP_TABLES`, which shows that `PARTITIONED BY (fl_registro_invalido)` is
accepted. `dados_api` shows `FAILED` only because it was stopped while starting; its
checkpoint is unaffected.

**Amendments** (owner, 2026-10-18, constitution v1.6.0): numbered files per zone; a
boundary view excluding `source_file_name` and `_rescued_data` before each zone change;
the rescued-data rule removed (owner's choice among three options); bronze and silver
declared as streaming only, with gold keeping materialized views.

**Rework done**:
- T003: bronze files renamed with `git mv`.
- T008: `01_vw_bronze_dados_api.sql` created.
- T009: `02_temp_tb_validacao_api.sql` created. It reads the view, has three rules and is
  partitioned. It replaces `temp_tb_validacao_api.sql`, which was removed locally.
- Spec, plan, research, data model, contract, quickstart and this task list were revised.

**T006** (recount, 14:57 UTC): unchanged after the owner's bronze refresh: `total`
2,550,955; `curso_invalido` 9,240; `valor_invalido` 9,240; `forma_pagamento_invalido`
6,934; `invalidos` 9,240. Latest bronze `processing_time` 13:57:09 UTC.

**T013**: uploaded. The four obsolete workspace files were deleted:
`01_bronze/dados_api.sql`, `01_bronze/dados_files.sql`, `01_bronze/dados_database.sql`
and `02_silver/temp_tb_validacao_api.sql`. The workspace now lists exactly the six
numbered files, all `FILE`.

**Quarantine keeps every field** (owner, 2026-10-18, 14:59 UTC): before the first
deployment of `tb_quarentena`, the owner asked that it carry all fields, to make data
issues easy to identify. They chose "all silver fields" and put the rule in the
constitution (Principle IV, v1.6.0). `03_tb_quarentena.sql` now selects `*` from the
validation table, keeping `regras_violadas`, `fl_registro_invalido`, `origem` and the
validation `data_carga`, and adds `data_carga_quarentena`. The background deploy started
at 14:57 was stopped at 14:59, before its dry run began. No update ran. The revised
file was uploaded and is identical to the repository.

**T014/T015 as run**: the owner started update `4a36cc07-...` from the UI at 15:02 UTC.
It was a normal update with the final code, and the CLI's dry run did not start because
of it. The update **failed**:
- `tb_quarentena` was created, and the `temp_tb_validacao_api` flow completed.
- The validation flow wrote into the private table's backing table. That table was
  created at 14:40 with the v1.5.0 schema, which still has `source_file_name` and
  `_rescued_data`, now always null.
- The quarantine flow read `*` from that table, got those two extra columns, and failed
  with `[DELTA_METADATA_MISMATCH] A metadata mismatch was detected when writing to the
  Delta table`. Unity Catalog does not allow automatic schema migration.

No normal update can fix the stale schema. **The owner approved** (2026-10-18, about
15:08 UTC) a refresh of only the two silver tables:
`--json '{"full_refresh_selection": ["workspace.silver.temp_tb_validacao_api",
"workspace.silver.tb_quarentena"]}'`. Bronze is not part of the selection.

Lesson for later features: a validate-only run creates no tables, and a failed first run
can still leave a backing table with an early schema. When a dataset's columns change
before it has ever completed, refresh it on the next run instead of hoping a normal
update reconciles the schema.

**Refresh `15f6ec69-b6f1-4c27-ae05-387a53863202`** (approved selection: the two silver
tables only): **COMPLETED**. It stands in for T014 and T015. The owner's update
`4a36cc07` had already validated and created the datasets in place of a separate dry run.

**T016**: `temp_tb_validacao_api` wrote **2,550,955** rows, equal to `total` (T006). The
bronze flows wrote nothing, because they were not in the refresh selection.

**T017**, expectations of `temp_tb_validacao_api`:

| rule | passed | failed | T006 |
|---|---|---|---|
| `curso_invalido` | 2,541,715 | 9,240 | 9,240 |
| `valor_invalido` | 2,541,715 | 9,240 | 9,240 |
| `forma_pagamento_invalido` | 2,544,021 | 6,934 | 6,934 |

For each rule, passed + failed = 2,550,955. No `ON VIOLATION` in any silver file.

**T019**: `tb_quarentena` has 9,240 rows, equal to `invalidos`. Per rule, from
`regras_violadas`: `curso_invalido` 9,240, `valor_invalido` 9,240,
`forma_pagamento_invalido` 6,934. These equal T006 and the `falhou` values of T017, so the
`CONSTRAINT` text and the `CASE` lines agree.

**T020**: `origem_errada`, `sem_data_carga`, `sem_data_carga_quarentena`, `flag_falsa` and
`sem_regra` are all 0. Columns, in order: `processing_time, access_date, access_point,
ip_address, payload, regras_violadas, fl_registro_invalido, origem, data_carga,
data_carga_quarentena`. There is no `source_file_name` or `_rescued_data`. Both
`EXCEPT ALL` sides are 0, so quarantine equals the invalid bronze events field for field.
`quality` = `silver`. `SHOW TABLES IN workspace.silver` lists only `tb_quarentena`; the
validation table is private.

**T021**: `regra_violada_registrada`: passed 9,240, failed 0.

**T022**: valid = 2,550,955 − 9,240 = **2,541,715**. This equals the passed count of
`curso_invalido` and `valor_invalido`, whose failures are exactly the invalid set. Bronze
2,550,955 = valid 2,541,715 + quarantined 9,240, with a difference of 0.

**T023**: update `95dabc19-68fe-47a2-9be4-f00d3418ee08` (no new landing data)
**COMPLETED**. The event log has no `num_output_rows` for any flow, so 0 rows were
written. `tb_quarentena` still has 9,240 rows. Incremental behavior is confirmed.

**T028**: the six workspace files are identical to the repository, with no unnumbered file
left. `explorations/setup/03_pipeline_dev.json` is unchanged. The owner committed the work
(commits `cb92128`, `29b90dc`, `60fda13`). The constitution was committed with its Sync
Impact Report still in the file.

**Open**: T018. The owner needs to look at the Data quality tab of
`temp_tb_validacao_api` in the pipeline UI. The event log already shows the three
expectations with their metrics (T017).

**File renumbering (2026-10-18, constitution v1.8.0)**: to follow the reading order of
`doc/lakeflow_architecture.png`, the silver files were renumbered. `02_temp_tb_validacao_api.sql`
became `03_temp_tb_validacao_api.sql`, and `03_tb_quarentena.sql` became
`04_tb_quarentena.sql`; `02_` is now `vw_bronze_dados_files` (feature 006). Content is
unchanged, so no dataset changed. Task texts above keep the names used when they ran.
