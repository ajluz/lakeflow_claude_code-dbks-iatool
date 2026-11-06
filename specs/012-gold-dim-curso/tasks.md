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

**Organization** (regenerated 2026-11-05, after the snapshot design was rejected; research,
Decision 9): three files in `src/pipeline/03_gold/`:
- `04_vw_gold_dim_curso_dados_database.sql` (in production);
- `05_vw_gold_dim_curso_membros.sql` (new);
- `06_dim_curso.sql`, renamed from `05_dim_curso.sql`.

Three ordinary pipeline updates, none of them a full refresh:
- US1 created the dimension with the course versions (done, update `3f2c2771`);
- US4 adds the members' once-only flow to the existing table;
- a final update with no change proves that rows and keys are stable.

T001–T007 were completed before the regeneration and are kept as done.

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

- [X] T001 Confirm the preconditions:
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

- [X] T002 Create `src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql`
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

- [X] T003 [US1] Create `src/pipeline/03_gold/05_dim_curso.sql`
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
- [X] T004 [US1] Upload `src/pipeline`, then confirm both new files are identical in the
  workspace (Conventions). Run a dry run.
  - Expect `COMPLETED`, with `dim_curso` and `vw_gold_dim_curso_dados_database` in the
    graph.
  - On failure, fix and repeat.
- [X] T005 [US1] Start an update (not a full refresh) and record its update id.
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

- [X] T006 [US2] Review `src/pipeline/03_gold/05_dim_curso.sql` and
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

- [X] T007 [US3] Review `src/pipeline/03_gold/05_dim_curso.sql` against User Story 3 and
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

**Goal**: rows `-1` and `-2`, one each, open, valid from 1900-01-01, with the course
versions untouched.

**Independent Test**:
- quickstart step 2 shows 5 rows, 2 members, and 1 row per member;
- quickstart step 3 shows the course key checksum still at `-380130840`.

- [X] T008 [US4] Create `src/pipeline/03_gold/05_vw_gold_dim_curso_membros.sql` in the
  batch form (research, Decision 9, form 1).
  - **Header comment in Portuguese**:
    - "Camada gold: membros padrão de dim_curso";
    - "Desconhecido (-1)" and "Não se aplica (-2)", for facts whose course is missing or
      does not apply;
    - the change time is 1900-01-01, so they are valid for any fact date and no course
      event closes them;
    - read once by `gold_dim_curso_membros_flow` (`AUTO CDC ONCE`), which then stays idle;
    - same columns and order as `vw_gold_dim_curso_dados_database`.
  - **Body**:

    ```sql
    CREATE TEMPORARY VIEW vw_gold_dim_curso_membros
    COMMENT 'Membros padrão de dim_curso, Desconhecido (-1) e Não se aplica (-2), no formato do fluxo AUTO CDC.'
    AS
    SELECT CAST(-1 AS BIGINT) AS sk_curso, '-1' AS curso_uuid,
           'Desconhecido' AS nome_curso, 'Desconhecido' AS nivel_curso,
           CAST(NULL AS DECIMAL(9,2)) AS valor_curso, current_timestamp() AS data_carga,
           'insert' AS change_type, TIMESTAMP'1900-01-01' AS timestamp_change
    UNION ALL
    SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica',
           CAST(NULL AS DECIMAL(9,2)), current_timestamp(), 'insert', TIMESTAMP'1900-01-01'
    ```

  - The members are "`Desconhecido` / `Não se aplica` in every text attribute, with an
    empty price, always current" (FR-008).
- [X] T009 [US4] Rename `src/pipeline/03_gold/05_dim_curso.sql` to
  `src/pipeline/03_gold/06_dim_curso.sql` (plain `mv`; the file is untracked). Change
  nothing in the existing table and change flow.
  - **Header**: replace the line "mais os membros padrão" with "mais os membros padrão,
    vindos de vw_gold_dim_curso_membros".
  - **Members flow**, appended after the change flow, preceded by a Portuguese comment:
    "Membros padrão, uma única vez (ONCE): o fluxo lê a view uma vez e fica ocioso, então
    os membros nunca são reenviados, nem quando chegam mudanças do catálogo. Mesmas
    cláusulas do fluxo das versões".

    ```sql
    CREATE FLOW gold_dim_curso_membros_flow AS AUTO CDC ONCE INTO workspace.gold.dim_curso
    FROM vw_gold_dim_curso_membros
    KEYS (curso_uuid)
    APPLY AS DELETE WHEN change_type = 'delete'
    SEQUENCE BY timestamp_change
    COLUMNS * EXCEPT (change_type, timestamp_change)
    STORED AS SCD TYPE 2;
    ```

- [X] T010 [US4] Switch the workspace over and validate.
  - Upload `src/pipeline`.
  - Delete the old workspace file
    (`databricks workspace delete $WS/03_gold/05_dim_curso.sql --profile databricks-free`):
    `import-dir --overwrite` does not remove it, and it would define `dim_curso` a second
    time.
  - Confirm `databricks workspace list $WS/03_gold` shows exactly `01_` to `04_`,
    `05_vw_gold_dim_curso_membros.sql` and `06_dim_curso.sql`, each identical to the
    repository.
  - Run a dry run.

  Decision path:
  - **`COMPLETED`**: go to T011.
  - **Rejected because the source is not a stream** (switch to form 2, research Decision 9):
    1. In `05_vw_gold_dim_curso_membros.sql`, rewrite the body as
       `SELECT m.* FROM STREAM(vw_bronze_tb_curso) AS c CROSS JOIN (<the two-row SELECT above>) AS m`.
       Add the header sentence "o stream do catálogo só dispara a emissão; as linhas de
       curso não são usadas".
    2. In `06_dim_curso.sql`, change the flow's source to
       `FROM STREAM(vw_gold_dim_curso_membros)`.
    3. Upload, confirm the copies are identical, and run the dry run again.
  - **Rejected for any other reason, or rejected again**, for example `ONCE` with SCD type 2:
    1. Restore the course-only state: put the first 25 lines of `06_dim_curso.sql` back as
       `05_dim_curso.sql`, and delete `05_vw_gold_dim_curso_membros.sql` and
       `06_dim_curso.sql`, both in the repository and in the workspace.
    2. Re-upload, confirm the copy is identical, and confirm the dry run is `COMPLETED`.
    3. Record the error and STOP. Report to the owner with Decision 10 as the fallback. No
       full refresh, no drop.
- [X] T011 [US4] At least 4 minutes after the last update, run an update (not a full
  refresh) and expect `COMPLETED`. Record the update id and which form (1 or 2) ran.
  - **Step 2**: `linhas` 5, `chaves` 5, `vazios` 0, `membros` 2, `chave_zero` 0,
    `cursos_atuais` 3, `fechadas` 0, `sem_carga` 0. The open-rows and one-row-per-member
    query returns 0 rows.
  - **Members query**: `-1 '-1' Desconhecido Desconhecido` and
    `-2 '-2' Não se aplica Não se aplica`, each with an empty `valor_curso`,
    `__START_AT` `1900-01-01 00:00:00` and an empty `__END_AT`.
  - **Step 3**: `linhas` 3 and `chk_sem_carga` `-380130840`; `so_gold` 0 and `so_silver` 0.
  - **`DESCRIBE`**: still the 8 columns.
  - **Stop condition**: if a course row changed or closed, or a member is missing,
    duplicated or closed, STOP. Record the evidence and report to the owner.

**Checkpoint**: all four stories are done, and the dimension is complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: key stability (SC-004), documentation (FR-013) and final validation.

- [X] T012 Record quickstart step 4 (`linhas`, `checksum`, with `data_carga` included).
  - At least 4 minutes after T011, run an update with no code or data change, and expect
    `COMPLETED`.
  - Repeat step 4. `linhas` must stay 5 and `checksum` must be identical (SC-004).
  - Note in the event log that `gold_dim_curso_membros_flow` did not run again, or ran with
    0 rows.
- [X] T013 [P] In `doc/pipeline-reference.md`:
  - **Rewrite `### dim_curso`**:
    - links to the three files (`04_vw_gold_dim_curso_dados_database.sql`,
      `05_vw_gold_dim_curso_membros.sql`, `06_dim_curso.sql` in `../src/pipeline/03_gold/`),
      "As built";
    - a streaming table with `gold_dim_curso_flow` (`AUTO CDC`, SCD type 2) and
      `gold_dim_curso_membros_flow` (`AUTO CDC ONCE`, members from the view, sequence
      1900-01-01);
    - the **bronze dependency**: it reads `bronze.dados_database` through
      `vw_bronze_tb_curso`, not `silver.tb_curso` (constitution, Principle I exception);
    - the same key, sequence and delete condition as `tb_curso`;
    - a column table: the 8 columns, with
      `sk_curso = xxhash64(curso_uuid, timestamp_change) & 9223372036854775807`, one per
      version, never reassigned;
    - the members;
    - the version lifecycle;
    - every event opens a version (no `TRACK HISTORY`);
    - current version: `__END_AT IS NULL`;
    - no expectations;
    - 5 rows on 2026-11-05;
    - updates and deletions are demonstrated at the talk;
    - why the members are not a snapshot flow: a snapshot can share a target with change
      flows only on SCD type 1.
  - **Add both views** to the list of gold views, next to `vw_gold_dim_usuario_tb_usuario`.
  - **Change the `vw_bronze_tb_curso` row** from "Read by `tb_curso` and, later,
    `dim_curso`" to "Read by `tb_curso` and by `dim_curso`'s flow view".
- [X] T014 [P] In `doc/known-issues.md`, under "Smaller items":
  - Delete the identity bullet ("An identity surrogate key is declared on an `AUTO CDC`
    target (`dim_curso`) in the earlier pipeline…"). No identity key remains.
  - Add a bullet: `AUTO CDC ... FROM SNAPSHOT` cannot share a target with change flows on
    SCD type 2 (`MULTI_QUERY_SNAPSHOT_TARGET_NOT_SUPPORTED`, feature 012). `dim_usuario`
    (SCD type 1) uses it; `dim_curso` loads its members with an `AUTO CDC ONCE` flow from a
    view instead.
  - Keep the bullet "`dim_curso` and `tb_curso` both read the bronze change feed".
- [X] T015 [P] In `doc/architecture.md`, update the features table:
  - point the "`AUTO CDC` as SCD type 2 (`__START_AT` / `__END_AT`)" row to
    [06_dim_curso.sql](../src/pipeline/03_gold/06_dim_curso.sql);
  - delete the "Explicit schema with identity surrogate keys" row;
  - add [04_vw_gold_dim_curso_dados_database.sql](../src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql)
    to the "Deterministic surrogate key" row;
  - add a row "Default members through a once-only `AUTO CDC ONCE` flow from a view
    (SCD type 2)", pointing to `05_vw_gold_dim_curso_membros.sql` and `06_dim_curso.sql`.

  Also:
  - in the mermaid graph, replace `B3 --> G2` with `V5 --> G2`;
  - after the graph, change "`dim_curso` reads the bronze change feed directly" to
    "reads the bronze change feed through `vw_bronze_tb_curso`".
- [X] T016 [P] In `doc/README.md`:
  - under `03_gold/`, add `04_vw_gold_dim_curso_dados_database.sql` ("Flow view:
    surrogate key per course version"), `05_vw_gold_dim_curso_membros.sql` ("Course
    dimension members -1 / -2") and `06_dim_curso.sql` ("Course dimension: AUTO CDC SCD
    type 2, members by a once-only flow"), moving the `└──` to the last file;
  - in "Pipeline datasets", gold becomes "3 streaming views, 2 streaming tables and 1
    materialized view".

  Also check that `doc/getting-started.md`'s CDC table still matches, and leave it
  unchanged if it does.
- [X] T017 Final validation:
  - the workspace `03_gold` holds exactly the six files, each identical to the repository;
  - rerun quickstart steps 2 and 3;
  - step 5 counts equal to T001;
  - the pipeline is `IDLE`;
  - stop the warehouse with `--no-wait`.
- [X] T018 Constitution review of the three `dim_curso` files:
  - current syntax only; no `CREATE OR REPLACE`, `APPLY CHANGES`, `LIVE.` or `FROM SNAPSHOT`;
  - no constraints, no `CLUSTER BY` / `PARTITIONED BY`;
  - three-level names for persisted datasets;
  - the delete clause before `SEQUENCE BY` in both flows;
  - `KEYS`, `SEQUENCE BY` and delete identical to `13_tb_curso.sql`;
  - no `UNION` across streams;
  - comments in Portuguese.

  Record the outcome, the update ids, the form used and the counts in Implementation Notes.
  Repeat plan Note A there.

---

## Dependencies & Execution Order

- **Done**: T001–T007 (Setup, Foundational, US1, and the US2/US3 reviews).
- **Then, in order**: T008 → T009 → T010 (decision path) → T011, then T012.
- T013–T016 touch different files and can run in parallel after T011.
- T017 runs after T012–T016; T018 runs last.

### Parallel opportunities

```text
After T011:   T013 (pipeline-reference), T014 (known-issues), T015 (architecture), T016 (README)
```

## Implementation Strategy

1. **MVP (done)**: T001–T005. The course versions are live.
2. **History behaviour (done)**: T006–T007, reviewed; their proof is the demo.
3. **Members**: T008–T011. Form 1, then form 2, then a revert and stop.
4. **Stability and polish**: T012 (an update in which nothing changes), then the docs, the
   checks and the review.

Pipeline time: two more updates, at least 4 minutes apart.

---

## Implementation Notes (2026-11-05)

**T001**: pipeline `IDLE`; `dim_curso` absent; `03_gold` held `01_`–`03_` only. Baseline:
`dados_database` 3 (all `insert`), `tb_curso` 3, `dim_usuario` 941,236, `dim_codigos` 62,
`tb_venda` 420,472, `tb_acesso` 2,516,192.

**T002–T005**: both files uploaded and identical. Dry run `a68a31b7` **COMPLETED**; update
`3f2c2771-51ad-44a1-b7ad-a782b472fceb` **COMPLETED** (not a full refresh). `dim_curso` is a
`STREAMING_TABLE`, `quality` = `gold`, with the 8 columns of FR-002 in order (`valor_curso`
`decimal(9,2)`, `__START_AT`/`__END_AT` `timestamp`). Step 2: `linhas` 3, `chaves` 3,
`vazios` 0, `membros` 0, `chave_zero` 0, `cursos_atuais` 3, `fechadas` 0, `sem_carga` 0, no
course with two open rows. Step 3: `so_gold` 0, `so_silver` 0; every `__START_AT` is
`2026-10-11 22:42:09.713` UTC. Step 4: `linhas` 3, `checksum` -2156297085 (key checksum
without `data_carga`: -380130840).

**T006–T007**: `KEYS (curso_uuid)`, `APPLY AS DELETE WHEN change_type = 'delete'` (before
`SEQUENCE BY`) and `SEQUENCE BY timestamp_change` appear identically in `13_tb_curso.sql` and
`05_dim_curso.sql`; `STORED AS SCD TYPE 2`; no `TRACK HISTORY`; the key includes
`timestamp_change`. The generator was not run; SC-006 is proven by the owner at the demo.

**T008–T009: BLOCKED.** The members' snapshot flow (research, Decision 5) is rejected by the
platform on this target:
- dry run `52ca7f0e` (ordinary): **FAILED**;
- dry run `fcadeef1`, with `full_refresh_selection` = `workspace.gold.dim_curso` (owner
  approved a full refresh of this table only): **FAILED** with the same error, so the real
  full refresh was not run.

  `[MULTI_QUERY_SNAPSHOT_TARGET_NOT_SUPPORTED] 'workspace.gold.dim_curso' already contains a
  APPLY CHANGES FROM SNAPSHOT query ... this API only supports one flow per destination.`

The same pattern works on `dim_usuario`, where both flows are SCD type 1; here both are SCD
type 2. After each failure the members flow was removed and the course-only file re-uploaded
(identical), so the pipeline is back to the state of update `3f2c2771`. The attempted flow is
kept in the scratchpad (`membros_flow_tentativa.sql`). Waiting for the owner's decision on how
to load the members.

**Regeneration (2026-11-05)**: the owner chose to load the members from a view before the
dimension (spec, Clarifications). T008–T018 were rewritten for research Decision 9: a
once-only `AUTO CDC ONCE` flow from `vw_gold_dim_curso_membros`, with `05_dim_curso.sql`
renamed to `06_dim_curso.sql`.

## Implementation Notes, after regeneration (2026-11-05)

**T008–T010**: `05_vw_gold_dim_curso_membros.sql` was created and `05_dim_curso.sql` renamed
to `06_dim_curso.sql`, with the members flow added. After the upload, the old workspace
`05_dim_curso.sql` was deleted.
- **Form 1**, the batch view: dry run `743688a7` **FAILED**: "Source data for the APPLY
  CHANGES target 'workspace.gold.dim_curso' must be a streaming query."
- **Form 2**, the members cross-joined to `STREAM(vw_bronze_tb_curso)`, with the flow
  reading `FROM STREAM(vw_gold_dim_curso_membros)`: dry run `6f2fe6be` **COMPLETED**.
  `AUTO CDC ONCE` is accepted with SCD type 2.

**T011**: update `105c6e2b-fea5-4d15-b5f2-2ee0a4ec3a0a` **COMPLETED**, ordinary, form 2.
- **Step 2**: `linhas` 5, `chaves` 5, `vazios` 0, `membros` 2, `chave_zero` 0,
  `cursos_atuais` 3, `fechadas` 0, `sem_carga` 0.
- **Open-rows / one-row-per-member query**: 0 rows. The three identical member rows per key
  that the first run read (one per change event) became exactly one row each.
- **Members**: `-1 '-1' Desconhecido Desconhecido` and `-2 '-2' Não se aplica Não se aplica`,
  `valor_curso` null, `__START_AT` `1900-01-01 00:00:00`, `__END_AT` null.
- **Step 3**: course `linhas` 3, `chk_sem_carga` -380130840 (unchanged from update
  `3f2c2771`); `so_gold` 0, `so_silver` 0.
- **Table**: 8 columns.

**T012**: before, `linhas` 5 and `checksum` -2812166466 (`max(data_carga)`
`2026-11-06 01:29:28.566` UTC). Update `cb2cff1f-7f69-48b7-aedf-3425843d7ad9` **COMPLETED**,
with no change. After, the same 5, the same checksum and the same `max(data_carga)`. The
event log shows `gold_dim_curso_membros_flow` "IDLE, waiting for new data" (SC-004).

**T013–T016**: documentation updated.
- `pipeline-reference.md`: `### dim_curso` rewritten; the `vw_bronze_tb_curso` row and the
  intro updated.
- `known-issues.md`: the identity bullet is replaced by the SCD 2 snapshot limitation.
- `architecture.md`: features rows, graph edge `V5 --> G2`, sentence after the graph.
- `README.md`: layout and gold count (3 streaming views, 2 streaming tables, 1 materialized
  view).
- `getting-started.md` already matched and is unchanged.

**T017**: the workspace `03_gold` holds exactly the six files, each identical to the
repository. Counts:

| Dataset | Rows |
|---|---|
| `dados_database` | 3 |
| `tb_curso` | 3 |
| `dim_usuario` | 941,236 |
| `dim_codigos` | 62 |
| `tb_venda` | 420,472 |
| `tb_acesso` | 2,516,192 |
| `dim_curso` | 5 |

The pipeline is `IDLE`; the warehouse is stopped.

**T018**: no `CREATE OR REPLACE`, `APPLY CHANGES`, `LIVE.`, `FROM SNAPSHOT`, constraints,
`CLUSTER BY` or `PARTITIONED BY`.
- `KEYS`, `SEQUENCE BY` and the delete clause are identical to `13_tb_curso.sql` in both
  flows, with the delete before `SEQUENCE BY`.
- The only `UNION ALL` joins the two literal member rows inside the cross-joined subquery.
  It is not a union across streams.
- Persisted datasets use three-level names. Comments are in Portuguese.
- **Note A** (plan): the constitution's sentence that `tb_curso` and `dim_curso` "carry the
  same price type and record source" no longer holds for the record source. It can be
  reworded through `/speckit-constitution`.

No full refresh or table drop was run. The full refresh the owner approved for the rejected
snapshot design was never executed.
