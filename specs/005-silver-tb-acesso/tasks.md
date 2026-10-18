---

description: "Task list for feature 005-silver-tb-acesso"
---

# Tasks: Silver Access Table from API Events

**Input**: Design documents from `/specs/005-silver-tb-acesso/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/silver-tb-acesso.md, quickstart.md

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

- **View statement shape** (`04_vw_silver_eventos_api.sql`): one short header comment in
  Portuguese, then exactly:

  ```sql
  CREATE TEMPORARY VIEW vw_silver_eventos_api
  COMMENT '<description in Portuguese>'
  AS
  SELECT
    *,
    try_to_timestamp(access_date) AS timestamp_acesso,
    CASE WHEN payload.info_usuario.nome IS NOT NULL
         THEN md5(concat_ws('||', coalesce(cast(timestamp_acesso AS STRING), ''), payload.info_usuario.nome))
    END AS usuario_uuid,
    CASE WHEN payload.info_produto.product_name IS NOT NULL
         THEN md5(payload.info_produto.product_name)
    END AS curso_uuid
  FROM STREAM(workspace.silver.temp_tb_validacao_api)
  WHERE NOT fl_registro_invalido;
  ```

- **Table statement shape** (`05_tb_acesso.sql`): one short header comment in Portuguese,
  then exactly:

  ```sql
  CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_acesso (
    CONSTRAINT check_endereco_ip_acesso EXPECT (endereco_ip_acesso IS NULL OR endereco_ip_acesso != '999.999.999.999') ON VIOLATION DROP ROW,
    CONSTRAINT check_local_acesso       EXPECT (local_acesso != 'unknown'),
    -- CONSTRAINT check_local_acesso    EXPECT (local_acesso != 'unknown') ON VIOLATION FAIL UPDATE,
    CONSTRAINT check_timestamp_acesso   EXPECT (timestamp_acesso IS NOT NULL),
    CONSTRAINT check_acesso_uuid        EXPECT (acesso_uuid IS NOT NULL)
  )
  COMMENT '<description in Portuguese>'
  TBLPROPERTIES ("quality" = "silver")
  AS
  SELECT
    timestamp_acesso,
    ip_address AS endereco_ip_acesso,
    CASE WHEN lower(access_point) IN ('iphone', 'android') THEN 'Mobile'
         WHEN lower(access_point) IN ('chrome', 'safari', 'firefox') THEN 'Computador'
         ELSE 'unknown'
    END AS local_acesso,
    md5(concat_ws('||',
        coalesce(cast(timestamp_acesso AS STRING), ''),
        coalesce(endereco_ip_acesso, ''),
        coalesce(local_acesso, ''))) AS acesso_uuid,
    usuario_uuid,
    curso_uuid,
    'API' AS origem,
    current_timestamp() AS data_carga
  FROM STREAM(vw_silver_eventos_api);
  ```

- **Allowed fallback, and only this one**: if a run rejects a lateral column alias
  (`timestamp_acesso` in the view, or `endereco_ip_acesso`/`local_acesso` in the table),
  compute the alias in a subquery in the `FROM` clause and keep the resulting columns and
  their order. Report anything else to the owner.
- **Forbidden**: see the contract's list. In short:
  - a read of bronze or of `tb_quarentena`;
  - `uuid()`, `rand()` or a load time inside a key;
  - bare `concat`;
  - recomputing `usuario_uuid` or `curso_uuid` outside the view;
  - an active `FAIL UPDATE`;
  - a materialized view;
  - a layout clause;
  - a column beyond the 8;
  - `LIVE`, `CREATE OR REPLACE`, `CREATE FLOW`;
  - a file without its `NN_` prefix.
- **Running against the workspace**: `--profile databricks-free` on every command. The
  pipeline is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.
- **SQL queries**: `databricks experimental aitools tools query "<sql>" --profile
  databricks-free --output csv`. Record every number in the Implementation notes.
- **Free Edition quota**: before every `start-update`:
  1. stop the SQL warehouse (`databricks warehouses stop f796ffb64302b6ba --profile databricks-free`);
  2. make sure no update of the owner's is running (`databricks pipelines get` shows `IDLE`);
  3. wait about 4 minutes after the previous update ended.

  A start that fails within seconds with `RESOURCE_EXHAUSTED` is the quota, not the code.
  A warehouse stuck in `STARTING` with the same message clears once the pipeline's
  compute is released.
- **Polling**: poll `databricks pipelines get-update <pipeline_id> <update_id>` to
  `COMPLETED`, `FAILED` or `CANCELED`. On `FAILED`, read the `ERROR` events from
  `databricks pipelines list-pipeline-events` and fix the cause.
- **Never** pass `--full-refresh` or `full_refresh_selection` without the owner's explicit
  approval for that run.
- **Why both files are complete before the first run**: a column added to a streaming
  table after rows were written is null on those rows. The 8 columns and the 4
  expectations therefore go in the first version of `05_tb_acesso.sql`, and the stories
  are delivered by proving parts of one deployed definition.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: confirm what this feature builds on

- [X] T001 Confirm that feature 004 is deployed, changing nothing. `databricks pipelines get 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free` shows `IDLE` and a latest update `COMPLETED`. `databricks workspace list /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline/02_silver --profile databricks-free` lists `01_vw_bronze_dados_api.sql`, `02_temp_tb_validacao_api.sql` and `03_tb_quarentena.sql`, with no `04_` or `05_` file yet

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the expected numbers, and a free target name

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Run the expected-counts query of quickstart.md step 1. Record `validos`, `ip_invalido`, `mantidos`, `unknown_mantidos` and `sem_timestamp` in the Implementation notes; on 2026-10-18 they were 2,541,715 / 25,523 / 2,516,192 / (to record) / 0. If `sem_timestamp` > 0, report it to the owner before writing code
- [X] T003 Run `SHOW TABLES IN workspace.silver` and confirm `tb_acesso` is not listed. If it is, stop and ask the owner. Then stop the SQL warehouse (Conventions)

**Checkpoint**: expected numbers recorded; the name is free

---

## Phase 3: User Story 1 - One conformed row per valid site access (Priority: P1) 🎯 MVP

**Goal**: `workspace.silver.tb_acesso` holds one row per valid API access, with `timestamp_acesso`, `endereco_ip_acesso` and `local_acesso`. It is built on a shared view of the valid events.

**Independent Test**: after the update of T009, `tb_acesso` has `mantidos` rows (T002), exactly the 8 columns, `local_acesso` only in {`Mobile`, `Computador`, `unknown`}, and no row from quarantine (quickstart.md step 3).

### Implementation for User Story 1

- [X] T004 [P] [US1] Create `src/pipeline/02_silver/04_vw_silver_eventos_api.sql` in the view statement shape of the Conventions. Use `COMMENT 'Eventos válidos da API (fl_registro_invalido = false), com timestamp_acesso e as chaves usuario_uuid e curso_uuid, definidas uma única vez.'`. The header comment in Portuguese says three things: the view reads only the valid side of `temp_tb_validacao_api`; it is the single definition of `usuario_uuid` and `curso_uuid` for the API source, which later tables must reuse; and `curso_uuid` equals the course catalog's identifier. Column rules from data-model.md:
  - `usuario_uuid` is "null when the event has no user";
  - `curso_uuid` is "null when the event has no product; equals the catalog's `curso_uuid`".
- [X] T005 [P] [US1] Create `src/pipeline/02_silver/05_tb_acesso.sql` in the table statement shape of the Conventions, with all 8 columns and all 4 expectations, plus the commented line. Use `COMMENT 'Acessos ao site vindos da API: um registro por acesso válido, com local de acesso e chaves de acesso, usuário e curso.'`. The header comment in Portuguese says:
  - the table shows the three expectation actions:
    - `check_endereco_ip_acesso` drops the row, as a declared exclusion that is not routed to quarantine (constitution v1.7.0, Principle IV);
    - `check_local_acesso` only counts;
    - the `FAIL UPDATE` variant, commented out on the next line, would stop the update;
  - to switch it on, comment out the active `check_local_acesso` line and uncomment the other.

  Column rules from data-model.md:
  - "Exactly these 8 columns, in this order";
  - `local_acesso` is "`iphone`/`android` → `Mobile`; `chrome`/`safari`/`firefox` → `Computador`; anything else, null included → `unknown` (case-insensitive)";
  - `acesso_uuid` is "not null (warn); unique in the table".
- [X] T006 [US1] Review both files against contracts/silver-tb-acesso.md:
  - the view reads only `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE NOT fl_registro_invalido`;
  - `usuario_uuid` and `curso_uuid` are computed only in the view;
  - the table reads only `STREAM(vw_silver_eventos_api)` and its select list has the 8 columns in order;
  - the `FAIL UPDATE` line is a comment directly after the active `check_local_acesso`;
  - `grep -n -E "uuid\(\)|rand\(\)|CLUSTER|PARTITIONED|MATERIALIZED|LIVE| concat\(" src/pipeline/02_silver/04_vw_silver_eventos_api.sql src/pipeline/02_silver/05_tb_acesso.sql` returns nothing.

**Checkpoint**: both definitions are written; they are deployed in Phase 4

---

## Phase 4: Deploy (shared by all stories)

**Purpose**: one upload, one dry run and one update

- [X] T007 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free`. Confirm that `02_silver` lists five `FILE`s: `01_` to `03_` unchanged, plus `04_vw_silver_eventos_api.sql` and `05_tb_acesso.sql`. Confirm that each workspace copy is identical to the repository (`databricks workspace export ... | diff - <file>`)
- [X] T008 Following the quota conventions, run a dry run with `databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --validate-only --profile databricks-free` and poll it to `COMPLETED`. The events must define `vw_silver_eventos_api` and `tb_acesso`. On a lateral-alias error, apply the allowed fallback, upload again and repeat. Report any other error
- [X] T009 Following the quota conventions, run the update with `databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free`, poll it to `COMPLETED` and record its `update_id`. If it fails after creating `tb_acesso`, and a fix changes the columns, **stop and ask the owner** to approve a refresh of `workspace.silver.tb_acesso` only. Confirm that `SHOW TABLES IN workspace.silver` lists `tb_acesso`

**Checkpoint**: `tb_acesso` exists and is filled

---

## Phase 5: User Story 1 - validation

- [ ] T010 [US1] Run the first two queries of quickstart.md step 3. Confirm:
  - `linhas` = `mantidos` (T002);
  - `categoria_errada`, `sem_timestamp`, `origem_errada` and `sem_data_carga` are 0;
  - the columns are `timestamp_acesso, endereco_ip_acesso, local_acesso, acesso_uuid, usuario_uuid, curso_uuid, origem, data_carga`;
  - `SHOW TBLPROPERTIES workspace.silver.tb_acesso ('quality')` is `silver`.

  Also run `SELECT local_acesso, count(*) FROM workspace.silver.tb_acesso GROUP BY 1` and confirm that the counts equal the T002-based expectation for each category. Record all numbers.

---

## Phase 6: User Story 2 - Reject impossible addresses and measure unknown devices (Priority: P1)

**Goal**: the address rule drops its rows, the device rule only counts, and the stopping rule is present but commented out.

**Independent Test**: quickstart.md step 4. For dataset `tb_acesso`, `check_endereco_ip_acesso` failed = `ip_invalido`, `check_local_acesso` failed = `unknown_mantidos`, and valid events = rows in `tb_acesso` + `ip_invalido`.

### Implementation for User Story 2

- [ ] T011 [P] [US2] Run the expectations query of feature 004's quickstart step 4 for the update of T009. Confirm that dataset `tb_acesso` lists exactly the four expectations, with failed counts:
  - `check_endereco_ip_acesso` = `ip_invalido` (T002);
  - `check_local_acesso` = `unknown_mantidos`;
  - `check_timestamp_acesso` = 0;
  - `check_acesso_uuid` = 0.

  Confirm that the `tb_acesso` flow wrote `mantidos` rows, and that `SELECT count(*) FROM workspace.silver.tb_acesso WHERE endereco_ip_acesso = '999.999.999.999'` is 0. Record the numbers.
- [ ] T012 [P] [US2] Reconcile (FR-014, SC-001): `validos` = rows in `tb_acesso` + failed of `check_endereco_ip_acesso`, with a difference of 0. Confirm that `tb_quarentena` did not grow (still 9,240), so the dropped rows were not quarantined
- [ ] T013 [US2] Confirm the commented rule: in `src/pipeline/02_silver/05_tb_acesso.sql`, the line after the active `check_local_acesso` starts with `--` and ends in `ON VIOLATION FAIL UPDATE,`; `grep -c "FAIL UPDATE" src/pipeline/02_silver/05_tb_acesso.sql` is 1, and that line is commented. Ask the owner to confirm that the pipeline UI's Data quality tab for `tb_acesso` shows the four expectations. Record the answer

**Checkpoint**: the three expectation actions are demonstrable

---

## Phase 7: User Story 3 - Stable keys to the access, the user and the course (Priority: P1)

**Goal**: `acesso_uuid` is deterministic, non-null and unique; `usuario_uuid` and `curso_uuid` recompute from their fields and are empty when nothing is referred to; `curso_uuid` joins the catalog.

**Independent Test**: quickstart.md step 3, last two queries, plus the uniqueness and null checks below.

### Implementation for User Story 3

- [ ] T014 [P] [US3] Run the key queries of quickstart.md step 3. Confirm:
  - `sem_chave` = 0, `chaves_repetidas` = 0 and `acesso_uuid_divergente` = 0;
  - `sem_catalogo` = 0, so every `curso_uuid` joins the course catalog.

  Record `com_curso`.
- [ ] T015 [P] [US3] Check the reference keys:
  - `SELECT count_if(usuario_uuid IS NULL) AS sem_usuario, count_if(curso_uuid IS NULL) AS sem_curso FROM workspace.silver.tb_acesso` gives counts consistent with the share of events without a user or product (research.md facts, minus dropped rows);
  - recomputing `usuario_uuid` on a sample of 1,000 rows from `vw_silver_eventos_api`'s expression, by joining back on `acesso_uuid` to bronze through the same derivations, matches. If a join-back query is too heavy on Free Edition, check `length(usuario_uuid) = 32` and `usuario_uuid RLIKE '^[0-9a-f]{32}$'` for all non-null rows instead, and say so in the notes.

**Checkpoint**: all three stories hold

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: incremental proof, the documentation required by FR-016, and the final review

- [ ] T016 Prove incremental behavior (FR-013, SC-008): following the quota conventions, run an update with no new landing data and poll it to `COMPLETED`. With the first event log query of feature 004's quickstart step 4 for that update, confirm that the `tb_acesso` flow wrote 0 rows and that the `tb_acesso` count is unchanged
- [X] T017 [P] In `doc/pipeline-reference.md`:
  - Rewrite `### tb_acesso` as built. Cover:
    - the file `src/pipeline/02_silver/05_tb_acesso.sql`;
    - that it reads `vw_silver_eventos_api`;
    - the 8 columns with their derivations;
    - the business key columns of `acesso_uuid` (`timestamp_acesso`, `endereco_ip_acesso`, `local_acesso`), `usuario_uuid` (`timestamp_acesso`, `payload.info_usuario.nome`) and `curso_uuid` (`payload.info_produto.product_name`);
    - the four expectations and their actions, and the commented `FAIL UPDATE`.
  - In `### Temporary views`, add `vw_silver_eventos_api`: file `04`; the valid events of `temp_tb_validacao_api`; the single definition of `timestamp_acesso`, `usuario_uuid` and `curso_uuid`.
  - In the API reconciliation line, add the declared exclusion: valid events = `tb_acesso` + rows dropped by `check_endereco_ip_acesso` (not quarantined, constitution v1.7.0).
  - Update the intro sentence to include `tb_acesso` and the view among the datasets "as built".
- [X] T018 [P] In `doc/architecture.md`:
  - In the mermaid graph, add a node for `vw_silver_eventos_api` (rounded, like the other views) and route `T1 --> <new view> --> S2`, replacing the direct `T1 --> S2`.
  - In the feature table, point "Expectations with `ON VIOLATION DROP ROW`" to `../src/pipeline/02_silver/05_tb_acesso.sql`, keeping the `tb_usuario` link.
  - Add a row "Expectation kept as a commented `FAIL UPDATE`" pointing to the same file.
- [X] T019 [P] In `doc/README.md`, add `04_vw_silver_eventos_api.sql` and `05_tb_acesso.sql` to the `02_silver/` layout with one-line descriptions, and update the "Pipeline datasets" row: in silver, 2 streaming views, 1 private streaming table and 2 streaming tables
- [ ] T020 Final review against contracts/silver-tb-acesso.md:
  - the two files match their shapes;
  - the workspace copies are identical to the repository;
  - `git status` shows changes only in `src/pipeline/02_silver/`, `doc/` and `specs/005-silver-tb-acesso/`;
  - feature 004's files are unchanged.

  Then complete the Implementation notes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **US1 definitions (Phase 3)** →
  **Deploy (Phase 4)** → validations of **US1 (Phase 5)**, **US2 (Phase 6)** and
  **US3 (Phase 7)**, in any order → **Polish (Phase 8)**
- T016 needs a quota cycle; run it after the validation queries and with the warehouse
  stopped

### User Story Dependencies

- **US1 (P1)**: builds the view and the table; every other story validates the same
  deployed definition
- **US2 (P1)** and **US3 (P1)**: depend only on the deploy; independent of each other

### Why one deploy

All 8 columns and 4 expectations must exist from the first run (Conventions), and each
update on Free Edition costs a quota cycle. One update creates both datasets, and each
story is then validated on its own.

### Parallel Opportunities

- T004 and T005 (two files)
- T011, T012, T014 and T015 (read-only queries)
- T017, T018 and T019 (three documentation files)

---

## Parallel Example: definitions

```bash
Task: "Create src/pipeline/02_silver/04_vw_silver_eventos_api.sql (T004)"
Task: "Create src/pipeline/02_silver/05_tb_acesso.sql (T005)"
```

## Parallel Example: validation

```bash
Task: "Expectation metrics of tb_acesso (T011)"
Task: "Reconciliation and quarantine unchanged (T012)"
Task: "Key recomputation, uniqueness and catalog join (T014)"
Task: "Reference key nulls and format (T015)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Setup + Foundational
2. Write both files (they are one deployable unit)
3. Deploy, then **STOP and VALIDATE** with T010

### Incremental Delivery

1. Expected numbers → definitions → one deploy
2. US1: rows, columns, categories (MVP)
3. US2: the three expectation actions and the reconciliation
4. US3: keys
5. Polish: incremental proof, documentation, review

---

## Notes

- What touches the workspace:
  - T001–T003 and T010–T015 only read.
  - T007 uploads two new files.
  - T008, T009 and T016 run updates. None refreshes an existing table.
- Commit after each phase checkpoint.

## Implementation notes

_To be completed during implementation._

### 2026-10-18

**T001**: pipeline `IDLE`, latest update `95dabc19-...` `COMPLETED`. `02_silver/` held
only feature 004's three files.

**T002** (15:44 UTC):

| validos | ip_invalido | mantidos | unknown_mantidos | Mobile | Computador | sem_timestamp |
|---|---|---|---|---|---|---|
| 2,541,715 | 25,523 | 2,516,192 | 117,131 | 1,262,684 | 1,136,377 | 0 |

**T003**: `SHOW TABLES IN workspace.silver` lists only `tb_quarentena`.

**T004–T006**: both files written. The review found no forbidden token. `usuario_uuid`
and `curso_uuid` are computed only in the view. `FAIL UPDATE` appears twice in
`05_tb_acesso.sql`, both as comments: the header and the commented rule line. T013's
`grep -c` therefore expects 2 commented occurrences, not 1.

**T007**: uploaded; all eight workspace files are identical to the repository, and
`02_silver/` lists five `FILE`s.

**T008**: the dry run `e79cfdfb-bd1a-4b2f-9f43-6f6f0047cc3d` (15:48 UTC) **COMPLETED**.
It defined `vw_silver_eventos_api` as a view and `tb_acesso` as a streaming table with an
append flow, so both lateral aliases were accepted. The CLI's real update could not start
at 15:52 (`Pipeline resources are being provisioned`). The owner had started update
`080eab80-...` from the UI at 15:49, which failed on the quota, and then the UI's
`START_RESOURCES` warm-up `a503afae-...` ran and completed at 15:52.

**T009**: update `cee901f0-476d-4411-8dbe-2219bfe4fca0` (CLI, 15:53 UTC) **COMPLETED**.
