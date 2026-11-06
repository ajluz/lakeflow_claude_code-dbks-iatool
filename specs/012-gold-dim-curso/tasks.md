---

description: "Task list for feature 012: gold course dimension (SCD type 2)"
---

# Tasks: Gold Course Dimension (SCD Type 2)

**Input**: Design documents from `/specs/012-gold-dim-curso/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/gold-dim-curso.md](contracts/gold-dim-curso.md),
[quickstart.md](quickstart.md)

**Tests**: no test tasks. The spec requests none, and the project has no test framework.
Each story is verified by the [quickstart.md](quickstart.md) queries named in its tasks.

**Organization**: two new files, `src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql`
and `src/pipeline/03_gold/05_dim_curso.sql`. Three ordinary pipeline updates, none of them
a full refresh:
- US1 creates the dimension with the course versions;
- US4 adds the members flow to the existing table, which also tests that the snapshot
  leaves course versions alone (research, Decision 5, Risk);
- a final update with no change proves that rows and keys are stable.

US2 (updates) and US3 (deletions) need no code of their own: they are the same flow.
During implementation they are verified by review, and they are proven by the owner at the
live demo. The generator's `update row` and `delete row` MUST NOT be run.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)

## Conventions for every task

- Profile `databricks-free`, passed explicitly; pipeline
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`; warehouse `f796ffb64302b6ba`.
- Workspace folder of the pipeline source:
  `WS=/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline`.
- Upload: `databricks workspace import-dir src/pipeline $WS --overwrite --profile databricks-free`.
  Then confirm each changed file is identical in the workspace, for example
  `databricks workspace export $WS/03_gold/05_dim_curso.sql --format AUTO --profile databricks-free | cmp - src/pipeline/03_gold/05_dim_curso.sql`.
- Dry run: `databricks pipelines start-update <id> --validate-only --profile databricks-free`.
  An update is the same command without `--validate-only`.
  - Poll `databricks pipelines get-update <id> <update_id>` until `COMPLETED` or `FAILED`.
  - On failure, read `error.exceptions[0].message` in
    `databricks pipelines list-pipeline-events`.
- Never `--full-refresh`, and never drop a table. Leave about 4 minutes between updates
  (Free Edition quota).
- Run SQL with `databricks experimental aitools tools query "<sql>" --profile databricks-free`.
- Stop the warehouse after each validation session with `--no-wait`.
- Code comments are in Portuguese; documentation is in English. zsh: never echo `=====`.

---

## Phase 1: Setup

**Purpose**: confirm the environment the plan assumes.

- [ ] T001 Confirm the preconditions:
  - the pipeline is `IDLE`
    (`databricks pipelines get 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free`);
  - `databricks tables get workspace.gold.dim_curso --profile databricks-free` reports
    that the table does not exist;
  - `databricks workspace list $WS/03_gold --profile databricks-free` shows only `01_`,
    `02_` and `03_` files.

  Record these counts for the "nothing else changed" check:
  - `workspace.bronze.dados_database`: expect 3, all `insert`, all with
    `timestamp_change` `2026-10-11 22:42:09.713` UTC;
  - `workspace.silver.tb_curso`: 3;
  - `workspace.gold.dim_usuario`: 941,236;
  - `workspace.gold.dim_codigos`: 62;
  - `workspace.silver.tb_venda`: 420,472;
  - `workspace.silver.tb_acesso`: 2,516,192.

---

## Phase 2: Foundational

**Purpose**: the flow view every story reads.

- [ ] T002 Create `src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql`
  (research, Decision 2 and Decision 3; data-model).
  - **Header comment in Portuguese**, in the style of
    `src/pipeline/03_gold/01_vw_gold_dim_usuario_tb_usuario.sql`:
    - "Camada gold: view do fluxo AUTO CDC de dim_curso";
    - it reads the course feed through `vw_bronze_tb_curso`, not `silver.tb_curso`,
      because SCD type 2 needs the change events (constitution, Principle I exception);
    - `sk_curso` is `xxhash64` of `curso_uuid` and `timestamp_change` with the sign bit
      cleared: one key per version, never changed, non-negative; negative keys are for the
      members;
    - `origem` and `processing_time` are left out (owner);
    - `change_type` and `timestamp_change` only drive the flow;
    - no filter and no rule on the feed.
  - **Statement**: `CREATE TEMPORARY VIEW vw_gold_dim_curso_dados_database`, with the
    Portuguese `COMMENT` 'Mudanças do catálogo de cursos com a chave substituta de cada
    versão, no formato do fluxo AUTO CDC de dim_curso.' and this body:

    ```sql
    AS
    SELECT
      xxhash64(curso_uuid, timestamp_change) & 9223372036854775807 AS sk_curso,
      curso_uuid,
      nome_curso,
      nivel_curso,
      valor_curso,
      data_carga,
      change_type,
      timestamp_change
    FROM STREAM(vw_bronze_tb_curso)
    ```

    No `WHERE`, no `CAST` and no other expression.

**Checkpoint**: the view exists. It is validated with the table in US1.

---

## Phase 3: User Story 1 - One dimension row per course version (Priority: P1) 🎯 MVP

**Goal**: `dim_curso` holds one open version per course, keyed per version, equal to silver.

**Independent Test**: quickstart steps 2 and 3. Expect 3 open course rows equal to
`silver.tb_curso`, no closed row, unique positive keys, the 8 columns, and no members yet.

- [ ] T003 [US1] Create `src/pipeline/03_gold/05_dim_curso.sql`
  (research, Decisions 1, 4, 6 and 7).
  - **Header comment in Portuguese**, in the style of `src/pipeline/03_gold/02_dim_usuario.sql`:
    - "Camada gold: dimensão de cursos (dim_curso). SCD tipo 2";
    - grain: one version of one course, plus the members;
    - `__START_AT` / `__END_AT` hold the change time of the event that opened and closed
      the version, and the current version is `__END_AT IS NULL`;
    - same key, order and delete condition as `silver.tb_curso` (Principle I);
    - an update closes the version and opens another; a delete closes it and removes
      nothing;
    - no `TRACK HISTORY`, because `sk_curso` and `data_carga` change on every event, and
      tracking only the attributes would overwrite the current version's key;
    - facts resolve the version by `curso_uuid` and the fact's time in
      `[__START_AT, __END_AT)`, using `-1` when nothing matches.
  - **Table**: `CREATE OR REFRESH STREAMING TABLE workspace.gold.dim_curso`, with the
    Portuguese `COMMENT` 'Dimensão de cursos com histórico (SCD tipo 2): uma linha por
    versão de cada curso, com chave substituta por versão, validade em __START_AT e
    __END_AT e os membros Desconhecido (-1) e Não se aplica (-2).' and
    `TBLPROPERTIES ("quality" = "gold")`.
    - No column list, no constraints (FR-009), no `CLUSTER BY` and no `PARTITIONED BY`.
  - **Flow**, preceded by a short Portuguese comment:

    ```sql
    CREATE FLOW gold_dim_curso_flow AS AUTO CDC INTO workspace.gold.dim_curso
    FROM STREAM(vw_gold_dim_curso_dados_database)
    KEYS (curso_uuid)
    APPLY AS DELETE WHEN change_type = 'delete'
    SEQUENCE BY timestamp_change
    COLUMNS * EXCEPT (change_type, timestamp_change)
    STORED AS SCD TYPE 2;
    ```

    The delete clause stays before `SEQUENCE BY`.
- [ ] T004 [US1] Upload `src/pipeline`, then confirm both new files are identical in the
  workspace (Conventions). Run a dry run.
  - Expect `COMPLETED`, with `dim_curso` and `vw_gold_dim_curso_dados_database` in the
    graph.
  - On failure, fix and repeat.
- [ ] T005 [US1] Start an update (not a full refresh) and record its update id.
  - Expect `COMPLETED` and no failed flow.
  - `databricks tables get workspace.gold.dim_curso` reports a `STREAMING_TABLE`.

  Then run the quickstart checks:
  - **Step 2**: `linhas` 3, `chaves` 3, `vazios` 0, `membros` 0 (members arrive in US4),
    `chave_zero` 0, `cursos_atuais` 3, `fechadas` 0, `sem_carga` 0. No `curso_uuid` has
    more than one open row.
  - **`DESCRIBE`**: exactly `sk_curso` BIGINT, `curso_uuid`, `nome_curso`, `nivel_curso`,
    `valor_curso` DECIMAL(9,2), `data_carga`, `__START_AT` TIMESTAMP and `__END_AT`
    TIMESTAMP. No `origem`, no `processing_time`, no change columns.
  - **`SHOW TBLPROPERTIES workspace.gold.dim_curso ('quality')`**: `gold`.
  - **Step 3**: `so_gold` 0 and `so_silver` 0. Every `__START_AT` equals
    `2026-10-11 22:42:09.713` UTC.

  Record step 4's `linhas` and `checksum`, which are used in T008.

**Checkpoint**: MVP. The course dimension exists, with one open version per course.

---

## Phase 4: User Story 2 - Updates keep the previous version (Priority: P1)

**Goal**: an update closes the open version and opens a keyed new one. This is proven at
the live demo.

**Independent Test**: at the demo, quickstart's "At the live demo" checks after
`update row`. During implementation, a review against the spec.

- [ ] T006 [US2] Review `src/pipeline/03_gold/05_dim_curso.sql` and
  `src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql` against User Story 2 and
  FR-003, FR-004 and FR-006.
  - `STORED AS SCD TYPE 2`, with no `TRACK HISTORY` (Decision 4).
  - `SEQUENCE BY timestamp_change` and `KEYS (curso_uuid)` are written identically to
    `src/pipeline/02_silver/13_tb_curso.sql`.
  - The key includes `timestamp_change`, so the new version gets its own key and the old
    one keeps its own.

  Do NOT run the generator. Record the review in Implementation Notes, along with the fact
  that SC-006 (update) is proven by the owner at the demo with quickstart's
  "At the live demo" queries.

**Checkpoint**: the update behaviour is declared and reviewed.

---

## Phase 5: User Story 3 - Deletions close the course without erasing it (Priority: P1)

**Goal**: a delete closes the open version and removes nothing. This is proven at the
live demo.

**Independent Test**: at the demo, quickstart's "At the live demo" checks after
`delete row`. During implementation, a review against the spec.

- [ ] T007 [US3] Review `src/pipeline/03_gold/05_dim_curso.sql` against User Story 3 and
  FR-005.
  - `APPLY AS DELETE WHEN change_type = 'delete'` is written identically to
    `src/pipeline/02_silver/13_tb_curso.sql` and placed before `SEQUENCE BY`.
  - The target is SCD type 2, so a delete sets `__END_AT` and keeps every row.
  - Out-of-order changes are placed by `timestamp_change`.

  Do NOT run the generator. Record the review in Implementation Notes, along with the fact
  that SC-006 (deletion) is proven by the owner at the demo.

**Checkpoint**: the delete behaviour is declared and reviewed.

---

## Phase 6: User Story 4 - Explicit members for unknown and not-applicable courses (Priority: P1)

**Goal**: rows `-1` and `-2`, open, valid from 1900-01-01, with the course versions
untouched.

**Independent Test**: quickstart step 2 shows 5 rows with 2 members; the members query
returns both; the course rows' checksum is unchanged from T005.

- [ ] T008 [US4] Add the members to `src/pipeline/03_gold/05_dim_curso.sql`, after the
  first flow (research, Decision 5).
  - **Portuguese comment**, adapted from `src/pipeline/03_gold/02_dim_usuario.sql`:
    - default members, loaded once;
    - a snapshot treats absent keys as deleted at its version, and the 1900 version is
      older than every course change, so no version is closed;
    - the members' `__START_AT` is 1900-01-01, so they are valid for any fact date;
    - "Não remova WITH VERSION".
  - **Flow**:

    ```sql
    CREATE FLOW gold_dim_curso_membros_flow AS AUTO CDC ONCE INTO workspace.gold.dim_curso
    FROM SNAPSHOT (
      SELECT CAST(-1 AS BIGINT) AS sk_curso, '-1' AS curso_uuid,
             'Desconhecido' AS nome_curso, 'Desconhecido' AS nivel_curso,
             CAST(NULL AS DECIMAL(9,2)) AS valor_curso,
             current_timestamp() AS data_carga
      UNION ALL
      SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica',
             CAST(NULL AS DECIMAL(9,2)), current_timestamp()
    )
    WITH VERSION (
      SELECT TIMESTAMP'1900-01-01' AS versao
      WHERE NOT EXISTS (SELECT 1 FROM last_snapshot_version())
    )
    KEYS (curso_uuid)
    STORED AS SCD TYPE 2;
    ```

    The members are "`Desconhecido` / `Não se aplica` in every text attribute, with an
    empty price, always current" (FR-008).
- [ ] T009 [US4] Upload, confirm the workspace copy is identical, and run a dry run. Then,
  at least 4 minutes after T005, run an update and expect `COMPLETED`.
  - **Step 2**: `linhas` 5, `chaves` 5, `membros` 2, `cursos_atuais` 3, `fechadas` 0,
    `vazios` 0, `chave_zero` 0, `sem_carga` 0.
  - **Members query**: `-1 '-1' Desconhecido Desconhecido` and
    `-2 '-2' Não se aplica Não se aplica`, each with an empty `valor_curso`,
    `__START_AT` `1900-01-01 00:00:00` and an empty `__END_AT`.
  - **Step 4 restricted to `WHERE sk_curso > 0`**: the same `linhas` (3) and `checksum`
    as T005.
  - **Step 3**: still 0 / 0.
  - **Stop condition** (plan): if any course row is closed, changed or missing, or a
    member is closed or missing, STOP. Record the evidence and report to the owner. Do not
    refresh, drop or work around it.

**Checkpoint**: all four stories are done, and the dimension is complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: key stability (SC-004), documentation (FR-013) and final validation.

- [ ] T010 Record quickstart step 4 (`linhas`, `checksum`, with `data_carga` included) on
  the whole table.
  - At least 4 minutes after T009, start an update with no code or data change, and expect
    `COMPLETED`.
  - Repeat step 4. `linhas` must stay 5 and `checksum` must be identical (SC-004): no
    change was read, and the snapshot flow is `ONCE`.
- [ ] T011 [P] In `doc/pipeline-reference.md`:
  - **Rewrite `### dim_curso`**:
    - links to [04_vw_gold_dim_curso_dados_database.sql](../src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql)
      and [05_dim_curso.sql](../src/pipeline/03_gold/05_dim_curso.sql), "As built";
    - a streaming table fed by `gold_dim_curso_flow` (`AUTO CDC`, SCD type 2) and
      `gold_dim_curso_membros_flow` (`AUTO CDC ONCE ... FROM SNAPSHOT`, members);
    - the **bronze dependency**: it reads `bronze.dados_database` through
      `vw_bronze_tb_curso`, not `silver.tb_curso` (constitution, Principle I exception);
    - the same key, sequence and delete condition as `tb_curso`;
    - a column table: the 8 columns of data-model.md, with
      `sk_curso = xxhash64(curso_uuid, timestamp_change) & 9223372036854775807`, one per
      version, never reassigned;
    - the members, at 1900-01-01;
    - the version lifecycle;
    - every event opens a version (no `TRACK HISTORY`);
    - current version: `__END_AT IS NULL`;
    - no expectations;
    - counts on 2026-11-05: 5 rows, 3 open courses;
    - updates and deletions are demonstrated at the talk.
  - **Add `vw_gold_dim_curso_dados_database`** wherever the gold views are listed, next to
    `vw_gold_dim_usuario_tb_usuario`.
  - **Change the `vw_bronze_tb_curso` row** from "Read by `tb_curso` and, later,
    `dim_curso`" to "Read by `tb_curso` and by `dim_curso`'s flow view".
- [ ] T012 [P] In `doc/known-issues.md`, under "Smaller items", delete the bullet "An
  identity surrogate key is declared on an `AUTO CDC` target (`dim_curso`) in the earlier
  pipeline…".
  - No identity key remains: `dim_usuario`, `dim_codigos` and `dim_curso` all use
    `xxhash64` keys.
  - If useful, keep the sentence about why identity is unsupported inside
    `dim_curso`'s reference section instead.
  - Keep the bullet "`dim_curso` and `tb_curso` both read the bronze change feed", which
    is by design.
- [ ] T013 [P] In `doc/architecture.md`, update the features table:
  - point the "`AUTO CDC` as SCD type 2 (`__START_AT` / `__END_AT`)" row to
    [05_dim_curso.sql](../src/pipeline/03_gold/05_dim_curso.sql);
  - delete the "Explicit schema with identity surrogate keys" row;
  - add [04_vw_gold_dim_curso_dados_database.sql](../src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql)
    to the "Deterministic surrogate key" row;
  - add `05_dim_curso.sql` to the "Default members … `AUTO CDC ONCE ... FROM SNAPSHOT`"
    row.

  Also:
  - in the mermaid graph, replace `B3 --> G2` with `V5 --> G2`;
  - in the sentence after the graph, change "`dim_curso` reads the bronze change feed
    directly" to "reads the bronze change feed through `vw_bronze_tb_curso`".
- [ ] T014 [P] In `doc/README.md`:
  - under `03_gold/`, add `04_vw_gold_dim_curso_dados_database.sql` ("Flow view: surrogate
    key per course version") and `05_dim_curso.sql` ("Course dimension: AUTO CDC SCD type
    2, members by snapshot"), moving the `└──` to the last file;
  - in "Pipeline datasets", gold becomes "2 streaming views, 2 streaming tables and 1
    materialized view".

  Also check that `doc/getting-started.md`'s change data capture table still matches,
  and leave it unchanged if it does.
- [ ] T015 Final validation:
  - the workspace copy of all five `03_gold` files matches the repository;
  - rerun quickstart steps 2 and 3 on the current state (5 rows; 0 / 0);
  - step 5: bronze `dados_database` 3, `tb_curso` 3, `dim_usuario` 941,236,
    `dim_codigos` 62, `tb_venda` 420,472 and `tb_acesso` 2,516,192, all equal to T001;
  - the pipeline is `IDLE`;
  - stop the warehouse with `--no-wait`.
- [ ] T016 Constitution review of both new files:
  - current syntax: `CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`,
    `CREATE FLOW ... AS AUTO CDC [ONCE] INTO`;
  - no `CREATE OR REPLACE`, no `APPLY CHANGES`, no `LIVE.`;
  - no constraints, no `CLUSTER BY` / `PARTITIONED BY`;
  - three-level names for persisted datasets;
  - the delete clause before `SEQUENCE BY`;
  - `KEYS`, `SEQUENCE BY` and delete identical to `13_tb_curso.sql`;
  - the view applies no filter or cast;
  - comments in Portuguese.

  Record the outcome, the update ids and the counts in an "Implementation Notes" section at
  the end of this file. Repeat plan Note A there: the constitution's sentence on the
  record source can be reworded through `/speckit-constitution`.

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2 → US1 → (US2, US3 reviews) → US4 → Phase 7.**
- Sequential tasks:
  - T003 needs T002, because the flow reads the view;
  - T004 needs T003, and T005 needs T004;
  - T006 and T007 need T003 (the code under review) and can run any time after it;
  - T008 edits the same file as T003, so it comes after it. It is uploaded only in T009,
    after T005's update, so that the snapshot is tested against existing course versions;
  - T009 needs T008 and the 4-minute gap;
  - T010 needs T009 and the 4-minute gap.
- T011–T014 touch different files and can run in parallel after T009, because the docs
  state the final 5 rows.
- T015 runs after T010–T014; T016 runs last.

### Parallel opportunities

```text
After T003:   T006 (US2 review) and T007 (US3 review), read-only
After T009:   T011 (pipeline-reference), T012 (known-issues), T013 (architecture), T014 (README)
```

The code tasks edit two files in order and stay sequential.

## Implementation Strategy

1. **MVP**: T001–T005. The course versions exist, one open per course, equal to silver.
2. **History behaviour**: T006–T007. Updates and deletions are reviewed; their proof is the
   demo.
3. **Members**: T008–T009. `-1` / `-2` are added by a second update, with the course rows
   unchanged.
4. **Stability and polish**: T010 (third update, nothing changes), then the docs, the final
   checks and the constitution review.

Pipeline time: three updates, each at least 4 minutes apart, about 15 minutes of waiting in
total.
