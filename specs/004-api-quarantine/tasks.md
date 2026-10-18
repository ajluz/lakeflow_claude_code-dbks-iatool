---

description: "Task list for feature 004-api-quarantine"
---

# Tasks: Validation and Quarantine of API Events

**Input**: Design documents from `/specs/004-api-quarantine/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/silver-validation-quarantine.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching step of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pipeline SQL (project code): `src/pipeline/02_silver/`
- Documentation: `doc/`
- All paths below are relative to the repository root

## Conventions for every task

- **The four rules**, fixed by data-model.md. They appear twice in the validation file:
  once as `CONSTRAINT` clauses, once as `CASE` lines. Both lists use this text and this
  order, character for character:

  | Order | Name | Condition (passes when true) |
  |---|---|---|
  | 1 | `curso_invalido` | `payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` |
  | 2 | `valor_invalido` | `payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00'` |
  | 3 | `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----'` |
  | 4 | `registro_nao_conforme` | `_rescued_data IS NULL` |

  The placeholder in rule 1 is exactly 32 lowercase `x`.

- **Validation statement shape**, fixed by the contract. One short header comment in
  Portuguese, then exactly this statement, with nothing added:

  ```sql
  CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api (
    CONSTRAINT curso_invalido           EXPECT (<rule 1>),
    CONSTRAINT valor_invalido           EXPECT (<rule 2>),
    CONSTRAINT forma_pagamento_invalido EXPECT (<rule 3>),
    CONSTRAINT registro_nao_conforme    EXPECT (<rule 4>)
  )
  CLUSTER BY (fl_registro_invalido)
  COMMENT '<description in Portuguese>'
  TBLPROPERTIES ("quality" = "silver")
  AS
  SELECT
    *,
    filter(
      array(
        CASE WHEN NOT (<rule 1>) THEN 'curso_invalido' END,
        CASE WHEN NOT (<rule 2>) THEN 'valor_invalido' END,
        CASE WHEN NOT (<rule 3>) THEN 'forma_pagamento_invalido' END,
        CASE WHEN NOT (<rule 4>) THEN 'registro_nao_conforme' END
      ),
      r -> r IS NOT NULL
    ) AS regras_violadas,
    size(regras_violadas) > 0 AS fl_registro_invalido,
    'API' AS origem,
    current_timestamp() AS data_carga
  FROM STREAM(workspace.bronze.dados_api);
  ```

- **Quarantine statement shape**, fixed by the contract. One short header comment in
  Portuguese, then exactly this statement:

  ```sql
  CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_quarentena (
    CONSTRAINT regra_violada_registrada EXPECT (size(regras_violadas) > 0)
  )
  COMMENT '<description in Portuguese>'
  TBLPROPERTIES ("quality" = "silver")
  AS
  SELECT
    * EXCEPT (fl_registro_invalido, data_carga),
    current_timestamp() AS data_carga
  FROM STREAM(workspace.silver.temp_tb_validacao_api)
  WHERE fl_registro_invalido;
  ```

- **Forbidden in either file**: `ON VIOLATION` (no `DROP ROW`, no `FAIL UPDATE`),
  `PARTITIONED BY`, `CAST`, renames or `EXCEPT` of a bronze column, `DISTINCT`,
  `GROUP BY`, joins, a `WHERE` in the validation file, a temporary view between bronze and
  validation, `CREATE FLOW`, `LIVE`, `CREATE OR REPLACE`, `APPLY CHANGES`, any catalog other
  than `workspace`, and any unqualified table name.
- **Allowed fallbacks after a dry run, and only these** (research.md Decision 2; contract):
  - If the lateral alias `size(regras_violadas)` is rejected, build `regras_violadas` in a
    subquery in the `FROM` clause over `STREAM(workspace.bronze.dados_api)`, and derive the
    flag, `origem` and `data_carga` in the outer `SELECT`. The resulting columns and their
    order do not change.
  - If the three-level name of the private table is rejected, or `CLUSTER BY` on a private
    table is rejected, **stop and report to the owner**. Do not drop the qualifier, do not
    remove `PRIVATE`, and never switch to `PARTITIONED BY`.
- **Why the validation file is complete from its first run**: a column added to a
  streaming table after rows were written would be null on those rows, and
  `fl_registro_invalido` must never be null (FR-003). So `regras_violadas`, the flag,
  `origem`, `data_carga` and the four constraints all go in the first version of the
  file.
- **Running against the workspace**: ask the owner which CLI profile to use before the
  first command, and pass `--profile <profile>` every time. Never choose a profile on the
  owner's behalf (feature 003 used `databricks-free`, but ask again). The pipeline is
  `lakeflow_dataslight_dev`, id `8d51ac7a-02be-4ce2-8afd-f4f263e448dd` (feature 003); confirm
  it in T002.
- **SQL queries**: run them with
  `databricks experimental aitools tools query "<sql>" --profile <profile> --output json`
  or in the workspace SQL editor. Record every number the tasks ask for in the
  Implementation notes at the end of this file.
- **Free Edition quota**: before every `start-update`, stop the SQL warehouse used for
  queries (`databricks warehouses list --profile <profile>`, then
  `databricks warehouses stop <warehouse_id> --profile <profile>`) and wait about a minute.
  Otherwise the update can fail with `RESOURCE_EXHAUSTED` (feature 003 implementation
  notes).
- **Polling**: after `start-update`, poll `databricks pipelines get-update <pipeline_id>
  <update_id> --profile <profile>` and read `.update.state` until `COMPLETED`, `FAILED` or
  `CANCELED`. On `FAILED`, read `error.exceptions[0].message` of the `ERROR` events from
  `databricks pipelines list-pipeline-events <pipeline_id> --profile <profile>` and fix the
  cause. Do not simply run again.
- **Never** pass `--full-refresh` or `full_refresh_selection` in these tasks. Both tables
  are new, so a normal update fills them from the start of bronze.
- **Event log queries** are those of quickstart.md step 4, with `<pipeline_id>` and the
  `<update_id>` of the update being checked filled in.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the silver folder and confirmation that the existing pipeline is the one to extend

- [X] T001 Create the folder `src/pipeline/02_silver/`
- [X] T002 Ask the owner for the CLI profile. Then, changing nothing: run `databricks pipelines get 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile <profile>` and confirm the name is `lakeflow_dataslight_dev`, `catalog` is `workspace`, `serverless` is `true`, and `libraries` is the single glob `/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline/**`; confirm its latest update is `COMPLETED`. If any of this differs, stop and ask the owner. `explorations/setup/03_pipeline_dev.json` is not changed by this feature

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the facts every story depends on, read before any code is written

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Read the `databricks-pipelines` skill at `.claude/skills/databricks-pipelines/SKILL.md` with `references/streaming-table-sql.md` and `references/expectations-sql.md`, as the constitution's workflow requires before pipeline code is written. Note in the Implementation notes any point where the skill disagrees with contracts/silver-validation-quarantine.md; if one exists, stop and raise it with the owner
- [X] T004 [P] Run `DESCRIBE TABLE workspace.bronze.dados_api` and confirm the columns are `processing_time`, `source_file_name`, `access_date`, `access_point`, `ip_address`, `payload`, `_rescued_data`. Then run `SELECT typeof(payload.info_pagamento.valor), typeof(payload.info_produto.product_name), typeof(payload.info_pagamento.forma_pagamento) FROM workspace.bronze.dados_api WHERE payload.info_pagamento IS NOT NULL LIMIT 1`. Record the three types in the Implementation notes (research.md Decision 4)
- [X] T005 Run the expected-counts query of quickstart.md step 1 against `workspace.bronze.dados_api` and record `total`, `curso_invalido`, `valor_invalido`, `forma_pagamento_invalido`, `registro_nao_conforme` and `invalidos` in the Implementation notes. If `curso_invalido`, `valor_invalido` or `forma_pagamento_invalido` is 0, stop and report it to the owner with the type recorded in T004. Do not change any literal on your own
- [X] T006 [P] Confirm nothing is in the way, changing nothing: `databricks tables list workspace silver --profile <profile>` shows no `tb_quarentena` and no `temp_tb_validacao_api`. If either exists, stop and ask the owner how to proceed

**Checkpoint**: the rules are known to catch real rows, and the target names are free

---

## Phase 3: User Story 1 - Mark every API event as valid or invalid (Priority: P1) 🎯 MVP

**Goal**: the private validation table holds every bronze API event, unchanged, with `regras_violadas` and a never-null `fl_registro_invalido`, clustered by the flag.

**Independent Test**: after one update, the event log shows that the validation flow wrote exactly `total` rows (T005), and the dry run accepted `PRIVATE`, the three-level name and `CLUSTER BY (fl_registro_invalido)`. The table is private, so its flag values are proven through the expectations (US2) and the quarantine table (US3).

### Implementation for User Story 1

- [X] T007 [US1] Create `src/pipeline/02_silver/temp_tb_validacao_api.sql` in the validation statement shape of the Conventions, with the four rules substituted verbatim. Use `COMMENT 'Eventos da API validados: cada evento do bronze, sem alteração, com as regras violadas e a flag fl_registro_invalido.'`. Add a header comment in Portuguese saying that this is the single validation of the API source at the bronze-to-silver boundary, that the expectations only measure, and that `fl_registro_invalido = true` goes to `tb_quarentena` while `false` goes on to the conformed tables. Lay out the four `CONSTRAINT` clauses and the four `CASE` lines so that the rules line up and can be compared line by line. Column rules from data-model.md: `regras_violadas` "empty array when none failed; never `NULL`"; `fl_registro_invalido` "never `NULL`"; `origem` "literal `'API'`… never `NULL`; not derived from the data"; `data_carga` "`current_timestamp()`… never `NULL`"
- [X] T008 [US1] Review `src/pipeline/02_silver/temp_tb_validacao_api.sql` against the contract: it is `PRIVATE`, three-level named, has `CLUSTER BY (fl_registro_invalido)` and `TBLPROPERTIES ("quality" = "silver")`; the four `CONSTRAINT` conditions equal the four `CASE WHEN NOT (...)` conditions character for character and in the same order; the select list order is `*`, `regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga`; nothing from the forbidden list appears (search the file for `ON VIOLATION`, `PARTITIONED`, `WHERE`, `LIVE`)
- [X] T009 [US1] Upload the pipeline source with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile <profile>`, and confirm with `databricks workspace list /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline/02_silver --profile <profile>` that `temp_tb_validacao_api.sql` is there as a file, not a notebook
- [ ] T010 [US1] Stop the SQL warehouse (Conventions), run a dry run with `databricks pipelines start-update <pipeline_id> --validate-only --profile <profile>`, and poll it to a terminal state. If `COMPLETED`, go on. If it failed on the lateral alias, apply the subquery fallback of the Conventions in `src/pipeline/02_silver/temp_tb_validacao_api.sql`, upload again (T009) and repeat. If it failed on the qualified private name or on `CLUSTER BY`, stop and report the exact error message to the owner. For any other error, fix the cause and repeat
- [ ] T011 [US1] Stop the SQL warehouse, run a real update with `databricks pipelines start-update <pipeline_id> --profile <profile>`, poll it to `COMPLETED`, and record its `update_id` in the Implementation notes. Confirm with `databricks tables list workspace silver --profile <profile>` that `temp_tb_validacao_api` is **not** listed, because it is private
- [ ] T012 [US1] With the first event log query of quickstart.md step 4 for the update of T011, confirm that the flow of `temp_tb_validacao_api` wrote exactly `total` rows (T005), so that no event was dropped (FR-002, SC-001), and that the bronze flows wrote 0 rows. Record the number

**Checkpoint**: every API event is classified; the split point exists

---

## Phase 4: User Story 2 - Count every rule violation in the pipeline's quality metrics (Priority: P1)

**Goal**: the four rules appear by name in the pipeline's data quality metrics, with failed counts equal to what bronze predicts, and no row is dropped.

**Independent Test**: quickstart.md step 4, expectations query. For `temp_tb_validacao_api`, the four names are listed, each `falhou` equals its count from T005, and `passou + falhou = total` for each rule.

### Implementation for User Story 2

- [ ] T013 [US2] Run the expectations query of quickstart.md step 4 for the update of T011. Confirm that dataset `temp_tb_validacao_api` lists exactly `curso_invalido`, `valor_invalido`, `forma_pagamento_invalido` and `registro_nao_conforme`; that each rule's `falhou` equals its count from T005; and that `passou + falhou = total` for each rule. Record the four `falhou` values. A mismatch means a `CONSTRAINT` and its `CASE` line differ: fix `src/pipeline/02_silver/temp_tb_validacao_api.sql` only after reporting it to the owner, because already-validated rows are not re-evaluated without a full refresh
- [ ] T014 [US2] Confirm that the rules only measure: the update of T011 is `COMPLETED`, not stopped by an expectation; `grep -n "ON VIOLATION" src/pipeline/02_silver/temp_tb_validacao_api.sql` returns nothing; and the row count of T012 equals `total`. Ask the owner to open the pipeline UI, select `temp_tb_validacao_api`, and confirm that the Data quality tab shows the four expectations with their metrics (completion gate 2). Record the answer

**Checkpoint**: every rule is measured and auditable

---

## Phase 5: User Story 3 - Keep invalid events in a quarantine table (Priority: P1)

**Goal**: `workspace.silver.tb_quarentena` holds exactly the flagged events, unchanged, each with the rules it broke, `origem = 'API'` and its own `data_carga`.

**Independent Test**: quickstart.md step 3. The quarantine count equals `invalidos` (T005); the per-rule counts equal T005's; both `EXCEPT ALL` sides return 0; no row lacks `origem`, `data_carga` or a rule name.

### Implementation for User Story 3

- [ ] T015 [US3] Create `src/pipeline/02_silver/tb_quarentena.sql` in the quarantine statement shape of the Conventions. Use `COMMENT 'Quarentena dos eventos da API rejeitados pela validação, sem alteração, com as regras violadas.'`. Add a header comment in Portuguese saying that the table receives the rows of `temp_tb_validacao_api` with `fl_registro_invalido = true`, keeps the original event unchanged so that it can be inspected and reprocessed, and records the rules in `regras_violadas`. Column rules from data-model.md: every bronze column has the "same name, type and value"; `regras_violadas` has "at least one name"; `origem` is `'API'`; `data_carga` is "when the row entered quarantine; replaces the validation table's value"; `fl_registro_invalido` "is not carried"
- [ ] T016 [US3] Review `src/pipeline/02_silver/tb_quarentena.sql` against the contract: it is a published (not `PRIVATE`) streaming table, three-level named, with `TBLPROPERTIES ("quality" = "silver")` and the single warn expectation `regra_violada_registrada`; it reads only `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE fl_registro_invalido`; the select list is `* EXCEPT (fl_registro_invalido, data_carga)` followed by `current_timestamp() AS data_carga`; nothing from the forbidden list appears
- [ ] T017 [US3] Upload the source as in T009 and confirm `tb_quarentena.sql` is in `.../lakeflow_dev/src/pipeline/02_silver` as a file. Stop the SQL warehouse, run a dry run with `--validate-only`, and poll it to `COMPLETED`. On failure, fix `src/pipeline/02_silver/tb_quarentena.sql` and repeat
- [ ] T018 [US3] Stop the SQL warehouse, run a real update, poll it to `COMPLETED`, and record its `update_id`. Confirm that `databricks tables list workspace silver --profile <profile>` lists `tb_quarentena` and still does not list `temp_tb_validacao_api`. With the first event log query of quickstart.md step 4 for this update, confirm that the `tb_quarentena` flow wrote exactly `invalidos` rows (T005), and that the `temp_tb_validacao_api` flow wrote 0 rows, since bronze did not grow
- [ ] T019 [US3] Run the two count queries of quickstart.md step 3 on `workspace.silver.tb_quarentena`. Confirm that the total equals `invalidos` (T005), and that the count of each rule from `explode(regras_violadas)` equals the same rule's count from T005 and its `falhou` from T013. Record the counts. A rule whose three numbers disagree means its `CONSTRAINT` and `CASE` line have drifted (research.md Decision 5)
- [ ] T020 [US3] Run the remaining queries of quickstart.md step 3. The checks query must return `origem_errada = 0`, `sem_data_carga = 0` and `sem_regra = 0`. Both `EXCEPT ALL` sides must return 0, proving that quarantine equals the invalid bronze rows field for field (FR-010, SC-005). Also run `SHOW TBLPROPERTIES workspace.silver.tb_quarentena ('quality')` and confirm the value is `silver`. Then run `databricks tables get workspace.silver.tb_quarentena --profile <profile>` and confirm that it is a streaming table carrying its Portuguese comment
- [ ] T021 [US3] Run the expectations query of quickstart.md step 4 for the update of T018. Confirm that dataset `tb_quarentena` lists `regra_violada_registrada` with `falhou = 0` and `passou = invalidos`

**Checkpoint**: invalid events are preserved with their reasons; nothing is silently discarded

---

## Phase 6: User Story 4 - Let valid events continue downstream (Priority: P2)

**Goal**: valid and quarantined events partition bronze exactly, and later runs process only new events.

**Independent Test**: bronze `total` = (`total` − `invalidos`) valid + quarantine count, with a difference of 0. A run with no new bronze rows adds 0 rows to both tables.

### Implementation for User Story 4

- [ ] T022 [US4] Reconcile (FR-013, SC-004). Compute valid = validation rows (T012) − quarantine rows (T019). Confirm that valid = `total` − `invalidos`, and that bronze `total` = valid + quarantined with a difference of 0. Because T020 proved that quarantine is exactly the invalid bronze set, every event is on exactly one side. Record the three numbers in the Implementation notes
- [ ] T023 [US4] Prove incremental behavior (FR-015, SC-007). Record the count of `workspace.silver.tb_quarentena`, stop the SQL warehouse, and run another update with no new landing data. Poll it to `COMPLETED`. With the first event log query of quickstart.md step 4 for this update, confirm that the `temp_tb_validacao_api` and `tb_quarentena` flows each wrote 0 rows. Confirm that the quarantine count did not change

**Checkpoint**: the split is exact and incremental; the valid side is ready for the conformed tables of later features

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: the documentation required by FR-018 (and by US4 scenario 3 for the consumer rule), and the final review

- [ ] T024 [P] In `doc/pipeline-reference.md`:
  - Remove the `vw_bronze_dados_api` row from the `### Temporary views` table: the new design reads bronze directly.
  - Rewrite `### temp_tb_validacao_api` for the new design. Cover:
    - the file `src/pipeline/02_silver/temp_tb_validacao_api.sql`;
    - that it is a private streaming table, clustered (not partitioned) by `fl_registro_invalido`, reading `workspace.bronze.dados_api` directly;
    - the table of the four rules, with conditions and "empty field passes";
    - the columns `regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga`;
    - that the expectations only measure;
    - the consumer rule: conformed silver tables built from API events must read `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE NOT fl_registro_invalido`, and must not restate the rules.
  - Rewrite `### tb_quarentena`. Cover:
    - the file `src/pipeline/02_silver/tb_quarentena.sql`;
    - that it is a streaming table of the flagged rows, every bronze column unchanged;
    - `regras_violadas`, `origem = 'API'`, and its own `data_carga`;
    - the expectation `regra_violada_registrada`;
    - that it has no hash key, because it is not a conformed table.
  - Add a reconciliation line: bronze `dados_api` = valid + quarantined, with no documented exclusion.
  - Change the intro paragraph so it says that these two Silver sections describe the pipeline as built under `src/pipeline/02_silver/`, while the other Silver sections and Gold still describe the earlier pipeline.
- [ ] T025 [P] In `doc/architecture.md`:
  - In the mermaid graph, delete the node line `V1([vw_bronze_dados_api])`, and change the edge `L1 --> B1 --> V1 --> T1` to `L1 --> B1 --> T1`. Leave the other edges unchanged.
  - In the "Lakeflow features demonstrated" table, point these rows to the new files instead of `code_tips/02_silver/03_temp_tb_validacao_api.sql` and `04_tb_quarentena.sql`:
    - "Temporary (pipeline-private) streaming table" → `../src/pipeline/02_silver/temp_tb_validacao_api.sql`;
    - "Expectations that only record violations" → the same file;
    - "Quarantine pattern (flag column + split)" → both new files.
  - Add a row "Liquid clustering (`CLUSTER BY`)" pointing to `temp_tb_validacao_api.sql`.
  - In the "Temporary streaming views" row, remove the link to `01_vw_bronze_dados_api.sql` and keep the other `vw_` files.
- [ ] T026 [P] In `doc/known-issues.md`, delete the table row for `04_tb_quarentena.sql:4` under `## Catalog name mismatch`, and delete the paragraph that begins "The quarantine table is the one that matters for the pipeline". The new quarantine reads `workspace.silver.temp_tb_validacao_api`. Keep the other rows of that section
- [ ] T027 Final review against contracts/silver-validation-quarantine.md:
  - The two files in `src/pipeline/02_silver/` match their statement shapes, apart from a fallback recorded in the Implementation notes, and contain nothing from the forbidden list.
  - The workspace copies are identical to the repository. Upload again if a file changed after its last upload; that also requires a further update, so report it.
  - `git status` shows changes only in `src/pipeline/02_silver/`, `doc/pipeline-reference.md`, `doc/architecture.md`, `doc/known-issues.md` and `specs/004-api-quarantine/`.
  - `explorations/setup/03_pipeline_dev.json` and `src/pipeline/01_bronze/` are unchanged.

  Then complete the Implementation notes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: requires features 001–003 in place, with `workspace.bronze.dados_api` populated
- **Foundational (Phase 2)**: depends on Setup; blocks all user stories
- **User Story 1 (Phase 3)**: depends on Foundational
- **User Story 2 (Phase 4)**: depends on US1's update (T011); adds no code, only proof
- **User Story 3 (Phase 5)**: depends on US1, since quarantine reads the validation table. It can run before or after US2, but T019 compares with T013, so run US2 first if possible
- **User Story 4 (Phase 6)**: depends on US1 and US3
- **Polish (Phase 7)**: depends on all four stories

### User Story Dependencies

- **US1 (P1)**: independent; creates the validation table
- **US2 (P1)**: needs US1's update; read-only
- **US3 (P1)**: needs US1's table; creates the quarantine table
- **US4 (P2)**: needs US1 and US3; read-only plus one no-change update

### Within Each User Story

- US1: write, review, upload, dry run, run, check; strictly in order
- US2: T013 before T014
- US3: write, review, upload and dry run, run, then T019–T021 in any order
- US4: T022 before T023, so that the reconciled counts are taken before the extra update

### Parallel Opportunities

- T003, T004 and T006 are independent reads
- T019, T020 and T021 are read-only queries and can run together
- T024, T025 and T026 edit three different documentation files
- The two SQL files are separate, but T015 is deliberately after US1's run so that the validation table is proven first. They could be written together if the owner prefers a single upload and update; the statement shapes do not change

---

## Parallel Example: Foundational

```bash
# Independent reads before any code:
Task: "Read the databricks-pipelines skill references (T003)"
Task: "DESCRIBE workspace.bronze.dados_api and record the rule field types (T004)"
Task: "Confirm tb_quarentena and temp_tb_validacao_api do not exist in workspace.silver (T006)"
```

## Parallel Example: User Story 3 validation

```bash
Task: "Quarantine counts per rule vs T005 and T013 (T019)"
Task: "origem / data_carga / regras_violadas checks, EXCEPT ALL both ways, properties (T020)"
Task: "regra_violada_registrada expectation metrics (T021)"
```

## Parallel Example: Polish

```bash
Task: "Rewrite the two silver sections of doc/pipeline-reference.md (T024)"
Task: "Update the graph and feature table of doc/architecture.md (T025)"
Task: "Remove the resolved quarantine entry from doc/known-issues.md (T026)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational. The rules are proven to catch real rows before any code exists
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: the validation flow wrote `total` rows, and the dry run accepted the private, clustered, three-level definition
5. The split point exists; quarantine and the conformed tables can now be built on it

### Incremental Delivery

1. Setup + Foundational → facts recorded, names free
2. User Story 1 → every event classified (MVP)
3. User Story 2 → every rule measured, with counts equal to bronze's prediction
4. User Story 3 → invalid events preserved with their reasons
5. User Story 4 → exact reconciliation and incremental behavior proven
6. Polish → documentation describes the validation and quarantine as built

---

## Notes

- What touches the workspace:
  - T002 and T004–T006 only read.
  - T009 and T017 upload files.
  - T010, T011, T017, T018 and T023 run pipeline updates. None is a full refresh.
  - Nothing writes to the landing volume.
- The first real update (T011) validates about 2.55 million events, the bronze count from
  feature 003. Allow a few minutes and keep polling.
- If a rule must change after T011, the already-validated rows keep their old
  classification. Re-evaluating them requires a full refresh of both tables, which needs
  the owner's approval and is not part of these tasks.
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
