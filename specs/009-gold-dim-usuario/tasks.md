---

description: "Task list for feature 009-gold-dim-usuario"
---

# Tasks: Gold User Dimension

**Input**: Design documents from `/specs/009-gold-dim-usuario/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/gold-dim-usuario.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching step of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Conventions for every task

- **Statement shape**: exactly that of contracts/gold-dim-usuario.md, with a header comment
  in Portuguese. The only allowed change: if `QUALIFY` inside a `UNION ALL` branch is
  rejected by the dry run, wrap the silver branch in a subquery. Report anything else.
- **Column order**: `sk_usuario`, `usuario_uuid`, `nome_usuario`, `email_usuario`,
  `idade_usuario`, `sexo_usuario`, `estado_usuario`, `profissao_usuario`,
  `empresa_usuario`, `origem`, `data_carga`. Types as in data-model.md.
- **Do not run the generators**: the course demo must reach the talk in its initial state
  (feature 008).
- **Workspace**: `--profile databricks-free` on every command. The pipeline is
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.
- **Free Edition quota**: before each `start-update`:
  1. stop the warehouse (`databricks warehouses stop f796ffb64302b6ba`), but **never while
     queries are still running on it**;
  2. make sure the pipeline is `IDLE`;
  3. wait about 4 minutes after the previous update.
- **Never** refresh an existing table without the owner's explicit approval. Record every
  update created in the implementation window (event log `create_update`), as feature 007
  did.

---

## Phase 1: Setup

- [X] T001 Confirm the starting state, changing nothing:
  - `databricks current-user me --profile databricks-free` succeeds (if the refresh token is invalid, **stop and ask the owner** to run `databricks auth login --profile databricks-free`);
  - the pipeline is `IDLE`, and its source glob is `.../lakeflow_dev/src/pipeline/**`;
  - the workspace has no `03_gold/` folder under `src/pipeline/`;
  - `SHOW TABLES IN workspace.gold` lists `dim_tempo` only;
  - `bronze.dados_database` still holds only the three inserts.

---

## Phase 2: Foundational

- [X] T002 Run quickstart.md step 1 and record the result in the Implementation notes. Expected: `usuarios` = `chaves` = `sk_distintas` = 941,234. If `sk_distintas` is lower, **stop and ask the owner**: a hash collision means the surrogate key needs a different design (research, Decision 2)

---

## Phase 3: User Story 1 - One dimension row per user (Priority: P1) 🎯 MVP

**Goal**: every silver user has one row in `dim_usuario`, with its attributes as in silver.

**Independent Test**: quickstart.md step 3. `linhas` = 941,236, `divergentes` = 0,
`api` = 741,234, `arquivo` = 200,000.

- [X] T003 [US1] Create `src/pipeline/03_gold/01_dim_usuario.sql` (new folder) exactly as in the contract:
  - `CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_usuario` with `check_sk_usuario` (`sk_usuario IS NOT NULL`) and `check_usuario_uuid` (`usuario_uuid IS NOT NULL`), both `ON VIOLATION FAIL UPDATE`, and `TBLPROPERTIES ("quality" = "gold")`;
  - the silver branch: `xxhash64(usuario_uuid) AS sk_usuario`, the nine silver columns unchanged, `current_timestamp() AS data_carga`, `FROM workspace.silver.tb_usuario` (no `STREAM`), `QUALIFY row_number() OVER (PARTITION BY usuario_uuid ORDER BY data_carga DESC) = 1`;
  - two `UNION ALL` member rows (Phase 5 defines their values; write them here, in the same file).

  The header comment in Portuguese states the grain (one user), SCD type 1, that `sk_usuario` is `xxhash64` of the business key so it never changes, the two members and their keys, and that facts resolve `sk_usuario` by joining on `usuario_uuid` and use `-1` when there is no match.

---

## Phase 4: User Story 2 - Surrogate keys that never change (Priority: P1)

**Goal**: `sk_usuario` keeps its value for every user across updates.

**Independent Test**: quickstart.md step 5. The saved pairs are identical after a second
update.

- [X] T004 [US2] Review `src/pipeline/03_gold/01_dim_usuario.sql` for key stability: `sk_usuario` comes only from `xxhash64(usuario_uuid)` or the literals `-1`/`-2`; there is no `IDENTITY`, `row_number()` used as a key, `monotonically_increasing_id()`, `uuid()` or `rand()`

---

## Phase 5: User Story 3 - Explicit members for unknown and not-applicable users (Priority: P1)

**Goal**: one "unknown" and one "not applicable" row, with fixed keys and readable labels.

**Independent Test**: quickstart.md step 3. `membros` = 2, and the two rows match the data
model.

- [X] T005 [US3] In `src/pipeline/03_gold/01_dim_usuario.sql`, the member rows are exactly: `sk_usuario` `CAST(-1 AS BIGINT)`, `usuario_uuid` `'-1'`, every text attribute (`nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`, `profissao_usuario`, `empresa_usuario`, `origem`) `'Desconhecido'`, `idade_usuario` `CAST(NULL AS INT)`; and `CAST(-2 AS BIGINT)`, `'-2'`, `'Não se aplica'`, `CAST(NULL AS INT)`; both with `current_timestamp() AS data_carga`. Review that each `UNION ALL` branch lists the 11 columns in the conventions' order

---

## Phase 6: Review and deploy (shared by all stories)

- [X] T006 Review the file against contracts/gold-dim-usuario.md: no `STREAM`, `STREAMING TABLE`, `workspace.bronze`, `dim_` read, `DROP ROW`, `dt_carga`, `PARTITIONED`, `CLUSTER` or `ai_`; exactly 11 columns in each branch
- [X] T007 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free`. Confirm that `03_gold/` lists `01_dim_usuario.sql` as `FILE`, identical to the repository (export with `--format AUTO` to stdout and `cmp`)
- [X] T008 Following the quota conventions, dry run (`--validate-only`) to `COMPLETED`, with `workspace.gold.dim_usuario` defined. Apply the allowed `QUALIFY` fallback if needed; report anything else
- [X] T009 Following the quota conventions, run the update to `COMPLETED`, and record its `update_id` and every update created in the window

---

## Phase 7: Validation

- [X] T010 [US1] Run quickstart.md step 3:
  - `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `api` 741,234; `arquivo` 200,000;
  - `divergentes` 0;
  - `sem_dimensao` 4,362 (users of sales that facts will resolve to `-1`);
  - the 11 columns of the data model, in order, `sk_usuario bigint`, `idade_usuario int`, `data_carga timestamp`;
  - `quality` = `gold`.
- [X] T011 [US3] From quickstart.md step 3, the member rows: exactly one row with `sk_usuario` `-1` (`'-1'`, `Desconhecido`) and one with `-2` (`'-2'`, `Não se aplica`), `idade_usuario` null in both
- [X] T012 Run quickstart.md step 4 for the update of T009: `check_sk_usuario` and `check_usuario_uuid` each passed 941,236, failed 0
- [X] T013 **Superseded: no expectations remain (T033), so there is nothing to confirm.** Ask the owner to confirm that the Data quality tab of `dim_usuario` shows the two expectations. Record the answer
- [X] T014 [US2] Run quickstart.md step 5: save the sample (the two members and five users), run a second update following the quota conventions (no new data), and confirm every `(usuario_uuid, sk_usuario)` pair is identical and `data_carga` is later

---

## Phase 8: Polish

- [X] T015 [P] In `doc/pipeline-reference.md`, rewrite `### dim_usuario` as built: file `../src/pipeline/03_gold/01_dim_usuario.sql`, materialized view over `silver.tb_usuario`, grain one user, SCD type 1, `sk_usuario = xxhash64(usuario_uuid)` and why, the 11 columns, the two members, the two `FAIL UPDATE` expectations, the counts of T010; and add `dim_usuario` to the intro's "as built" list
- [X] T016 [P] In `doc/architecture.md`, in the features table, replace the `01_dim_usuario.sql` link in "Explicit schema with identity surrogate keys" by removing it from that row, and add `../src/pipeline/03_gold/01_dim_usuario.sql` to the "Materialized views" row; add a row "Deterministic surrogate key (`xxhash64` of the business key) and default members" → the same file
- [X] T017 [P] In `doc/README.md`, add `03_gold/` to the `src/pipeline/` layout with `01_dim_usuario.sql` ("User dimension: materialized view, stable hash surrogate key, unknown / not-applicable members"), turning the `02_silver/` branch into `├──` and its children's prefix into `│       │   `; change the dataset count's "gold not built yet" to "in gold, 1 materialized view (plus `dim_tempo`, created outside the pipeline)"
- [X] T018 [P] In `doc/known-issues.md`, in the smaller item on identity surrogate keys, remove `dim_usuario` and state that it now uses a deterministic `xxhash64` key (feature 009) and that identity columns are not supported on materialized views (`databricks-pipelines` skill)
- [X] T019 Final review:
  - the workspace copy is identical to the repository;
  - `git status` shows changes only in `src/pipeline/03_gold/`, `doc/` and `specs/009-gold-dim-usuario/`;
  - silver and bronze files are unchanged; `bronze.dados_database` still holds only the three inserts.

  Complete the Implementation notes.

---

## Dependencies & Execution Order

- Setup (T001) → Foundational (T002) → the file (US1 T003, US2 review T004, US3 T005) →
  review and deploy (T006–T009) → validation (T010–T014) → Polish (T015–T019).
- T002 blocks the file: a hash collision would change the design.
- All three stories live in one file, `01_dim_usuario.sql`, so T003, T004 and T005 run in
  sequence on it. They are deployed together and validated separately.
- T014 needs a second update, which also serves as the no-new-data check.
- Parallel: T015, T016, T017 and T018 (separate docs).

## Parallel Example

```text
After T014:
  T015 pipeline-reference.md | T016 architecture.md | T017 README.md | T018 known-issues.md
```

## Implementation Strategy

One file and one deploy. MVP = US1 validated (T010). US3 (T011) is proven by the same
run; US2 (T014) needs the second update.

## Implementation notes

### 2026-10-28

**T001**: login valid; pipeline `IDLE` (last update `3c52c735`, feature 008), glob
`.../lakeflow_dev/src/pipeline/**`; workspace `src/pipeline/` held `01_bronze` and
`02_silver` only; `workspace.gold` held `dim_tempo` only; `bronze.dados_database` still 3
inserts.

**T002**: `usuarios` = `chaves` = `sk_distintas` = 941,234: no `xxhash64` collision. No
user hashes to `-1` or `-2` (`sk_membro` 0).

**T003–T006**: `src/pipeline/03_gold/01_dim_usuario.sql` written. One change from the
contract's text, within its "layout is the implementer's" note: the silver branch reads
`tb_usuario AS u` and orders by `u.data_carga`, because the branch's own output column is
also named `data_carga` (`current_timestamp()`), and an unqualified name in `QUALIFY`
could resolve to that alias and order by a constant. No reassignable key function (T004).
The members are as specified (T005). No forbidden token; each of the three branches lists
the 11 columns in order (T006).

**T007**: upload complete; `03_gold/` lists `01_dim_usuario.sql` as `FILE`, identical to
the repository. Warehouse stopped.

**T008**: dry run `387a2bcc-2920-42c5-b172-ac387a60f14e` **COMPLETED**, no error;
`workspace.gold.dim_usuario` defined. The `QUALIFY` fallback was not needed.

**T009**: update `14bc317d-8806-4132-bc65-922ada98d287` **COMPLETED**. Updates in the
window: `387a2bcc` (dry run) and `14bc317d`, both `API_CALL`, neither a full refresh.

**T010**: `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `membros` 2; `api` 741,234;
`arquivo` 200,000; `divergentes` 0; `sem_dimensao` 4,362. Columns, in order:
`sk_usuario bigint, usuario_uuid string, nome_usuario string, email_usuario string,
idade_usuario int, sexo_usuario string, estado_usuario string, profissao_usuario string,
empresa_usuario string, origem string, data_carga timestamp`. `quality` = `gold`.

**T011**: `-1` / `'-1'` with every text attribute `Desconhecido` and age null; `-2` / `'-2'`
with `Não se aplica` and age null. **Finding**: the quickstart's member query used
`sk_usuario < 0`, which hit the result-size limit: `xxhash64` is signed, so 471,020 of the
941,234 real users have a negative key (470,214 positive). Keys remain unique and none
equals `-1` or `-2`, but `sk_usuario < 0` does not select the members. The quickstart now
selects `sk_usuario IN (-1, -2)`, and `doc/pipeline-reference.md` warns against `< 0`. The
key design is unchanged, as specified; changing it is the owner's decision (see Open).

**T012**: update `14bc317d`: `check_sk_usuario` and `check_usuario_uuid` each passed
941,236, failed 0.

**T013**: open, for the owner.

**T014**: second update `1f88dc5a-5096-49c9-af5a-11831ea5ac02` (no new data, `API_CALL`,
no full refresh) **COMPLETED**. The seven saved pairs (both members and the five lowest
`usuario_uuid`) are identical before and after; `data_carga` moved from
22:19:26.979Z to 22:38:58.183Z on every row; still 941,236 rows and keys. This update is
also the no-new-data check.

**T015–T018**: `doc/pipeline-reference.md` (`### dim_usuario` as built, intro),
`doc/architecture.md` (identity row without `dim_usuario`; materialized views row; new row
for the deterministic key and members), `doc/README.md` (`03_gold/` in the layout; gold
count) and `doc/known-issues.md` (identity item restated without `dim_usuario`).

**T019**: the workspace copy is identical to the repository. The owner committed the file
and most docs during implementation (`f7360b6`, `89f5afd`); uncommitted are
`doc/pipeline-reference.md`, `specs/009-gold-dim-usuario/quickstart.md` and this file.
Silver and bronze files are unchanged; `bronze.dados_database` still holds the three
inserts.

**Open (owner)**:
- T013: the Data quality tab of `dim_usuario`.
- Negative surrogate keys: keep `xxhash64` as is, or make every real key positive (for
  example `xxhash64(usuario_uuid) & 9223372036854775807`), so that negative values mean
  only the members. Changing it now is cheap: no fact uses `sk_usuario` yet, and the view
  is recomputed on the next update. After `fato_venda` exists, it would change every fact
  row's key.
- The flow-name finding (pipeline-wide).

---

## Phase 9: Convergence

Owner direction, 2026-11-04: rebuild `dim_usuario` as an `AUTO CDC` SCD type 1 streaming
table. These tasks supersede the materialized view of T003–T006 and the key expression of
T003. The conventions at the top of this file still apply. `dim_curso` and `dim_codigos`
are out of scope.

- [X] T020 Update `specs/009-gold-dim-usuario/` to the new design before any code changes, per owner direction 2026-11-04 and FR-004 (contradicts)
  - `spec.md`: add a 2026-11-04 clarification session recording the `AUTO CDC` decision, why identity was rejected, and the new `data_carga` meaning. Reword FR-002, FR-004, SC-004, the "user disappears" edge case (silver has no delete event, so the row stays) and the assumptions. `data_carga` becomes the time gold last wrote the row, and SC-004 expects it to stay unchanged on an update with no new data.
  - `plan.md`: rewrite the summary, technical context, structure and design notes. In the Constitution Check, record two deviations with justification: no delete condition (Principle V; the source has no delete event) and a flow view the diagram does not draw (the `AUTO CDC` flow cannot compute columns).
  - `research.md`: replace Decisions 1, 2, 3 and 5. Record the rejected options: identity on the target (not supported on `AUTO CDC` targets), a downstream Delta table with `INSERT` (Principle II), and `row_number()` or `monotonically_increasing_id()` (Principle VII).
  - `data-model.md`, `contracts/gold-dim-usuario.md`, `quickstart.md`: match T022, T023 and T027, and remove `STREAM` and `STREAMING TABLE` from the contract's forbidden list.
- [X] T021 Run this check on the workspace and record the result, per FR-005 and SC-002 (partial): `SELECT count(*), count(DISTINCT usuario_uuid), count(DISTINCT xxhash64(usuario_uuid) & 9223372036854775807), count_if(data_carga IS NULL) FROM workspace.silver.tb_usuario`. Expected: the first three are equal and the last is 0. **Stop and ask the owner** if the third is lower (hash collision) or the last is not 0 (`AUTO CDC` rejects a null sequence). Also confirm silver's `data_carga` is `TIMESTAMP`
- [X] T022 Create `src/pipeline/03_gold/01_vw_gold_dim_usuario_tb_usuario.sql` with a Portuguese header comment, per FR-004 and FR-005 (contradicts)
  ```sql
  CREATE TEMPORARY VIEW vw_gold_dim_usuario_tb_usuario AS
  SELECT
    xxhash64(usuario_uuid) & 9223372036854775807 AS sk_usuario,
    usuario_uuid, nome_usuario, email_usuario, idade_usuario, sexo_usuario,
    estado_usuario, profissao_usuario, empresa_usuario, origem,
    current_timestamp() AS data_carga,
    data_carga          AS data_carga_silver
  FROM STREAM(workspace.silver.tb_usuario);
  ```
  The mask keeps every real key non-negative, so negative keys mean only the members. This closes the "negative surrogate keys" open item.
- [X] T023 Create `src/pipeline/03_gold/02_dim_usuario.sql` with a Portuguese header comment stating the grain, SCD type 1, the key expression and the members, per FR-001, FR-004, FR-007 and FR-008 (missing)
  ```sql
  CREATE OR REFRESH STREAMING TABLE workspace.gold.dim_usuario (
    sk_usuario BIGINT, usuario_uuid STRING, nome_usuario STRING, email_usuario STRING,
    idade_usuario INT, sexo_usuario STRING, estado_usuario STRING,
    profissao_usuario STRING, empresa_usuario STRING, origem STRING, data_carga TIMESTAMP,
    CONSTRAINT check_sk_usuario   EXPECT (sk_usuario IS NOT NULL)   ON VIOLATION FAIL UPDATE,
    CONSTRAINT check_usuario_uuid EXPECT (usuario_uuid IS NOT NULL) ON VIOLATION FAIL UPDATE
  )
  COMMENT '<Portuguese>'
  TBLPROPERTIES ("quality" = "gold");

  CREATE FLOW gold_dim_usuario_tb_usuario_flow AS AUTO CDC INTO workspace.gold.dim_usuario
  FROM STREAM(vw_gold_dim_usuario_tb_usuario)
  KEYS (usuario_uuid)
  SEQUENCE BY data_carga_silver
  COLUMNS * EXCEPT (data_carga_silver)
  STORED AS SCD TYPE 1;

  CREATE FLOW gold_dim_usuario_membros_flow AS AUTO CDC ONCE INTO workspace.gold.dim_usuario
  FROM SNAPSHOT (
    SELECT CAST(-1 AS BIGINT) AS sk_usuario, '-1' AS usuario_uuid,
           'Desconhecido' AS nome_usuario, 'Desconhecido' AS email_usuario,
           CAST(NULL AS INT) AS idade_usuario, 'Desconhecido' AS sexo_usuario,
           'Desconhecido' AS estado_usuario, 'Desconhecido' AS profissao_usuario,
           'Desconhecido' AS empresa_usuario, 'Desconhecido' AS origem,
           current_timestamp() AS data_carga
    UNION ALL
    SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica', CAST(NULL AS INT),
           'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica',
           'Não se aplica', current_timestamp()
  )
  WITH VERSION (
    SELECT TIMESTAMP'1900-01-01' AS versao
    WHERE NOT EXISTS (SELECT 1 FROM last_snapshot_version())
  )
  KEYS (usuario_uuid)
  STORED AS SCD TYPE 1;
  ```
  **Keep `WITH VERSION`.** A snapshot treats absent keys as deleted at its version. The 1900 version keeps it older than every silver row, so users are not deleted. Without it, the implicit version is the load time, which would be newer than the silver rows.
- [X] T024 Delete `src/pipeline/03_gold/01_dim_usuario.sql` and review the two new files, per FR-011 (contradicts): no `IDENTITY`, `row_number()`, `monotonically_increasing_id()`, `MATERIALIZED VIEW`, `workspace.bronze`, `DROP ROW`, `dt_carga`, `PARTITIONED`, `CLUSTER` or `ai_`; exactly the 11 columns of FR-002 reach the target
- [X] T025 **Ask the owner to approve dropping `workspace.gold.dim_usuario`, and do not continue without it**, per Constitution, Development Workflow: dataset type change (missing). After approval, drop the materialized view, delete `03_gold/01_dim_usuario.sql` from the workspace (`import-dir --overwrite` does not remove it, and two files would define the same table), then upload `src/pipeline` and confirm the workspace copy is identical to the repository
- [X] T026 Following the quota conventions, dry run to `COMPLETED`, then run the update to `COMPLETED`, and record every update created in the window, per FR-001 and FR-007 (missing). **If the dry run rejects `AUTO CDC ... FROM SNAPSHOT`, `WITH VERSION`, or the target shape, stop and ask the owner; do not improvise another design.** SQL snapshot CDC needs DBR 18.3 or later, and the pipeline's runtime is not yet confirmed. Do not run a full refresh
- [X] T027 Run the updated quickstart.md and record the results, per SC-001 to SC-006 and US1 to US3 (missing)
  - `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `api` 741,234; `arquivo` 200,000; `divergentes` 0 (comparing against the masked key); `sem_dimensao` 4,362. **If `linhas` is near 2, the snapshot deleted the users: stop and ask the owner.**
  - `count_if(sk_usuario < 0)` = 2, and those rows are the two members as in T011.
  - The 11 columns in order, with no system columns visible; `quality` = `gold`.
  - Record the observed metrics of both expectations. The snapshot flow defines no expectations, so 941,234 passed is plausible instead of 941,236. Failed must be 0.
  - Save the T014 sample, run a second update with no new data, and confirm every pair, row count and `data_carga` value is unchanged.
  - Record that the overwrite path of FR-004 was not exercised: silver has no repeated key, and the generators must not run.
- [X] T028 Rewrite `### dim_usuario` in `doc/pipeline-reference.md` as built, including the new key, members, `data_carga` meaning and counts of T027, and remove its negative-key warning. Update the `doc/architecture.md` feature rows (`AUTO CDC` SCD type 1, and no longer a materialized view), the `doc/README.md` layout and dataset count, and the identity item in `doc/known-issues.md`, per FR-012 (partial)
- [X] T029 **The Data quality question no longer applies (T033).** Ask the owner to confirm that the Data quality tab of the rebuilt `dim_usuario` shows both expectations (replaces open task T013). Add a 2026-11-04 section to the Implementation notes, and confirm `git status` shows changes only in `src/pipeline/03_gold/`, `doc/` and `specs/009-gold-dim-usuario/`, per T013 and T019 (partial)

## Phase 10: Members revision

The dry run of T026 rejected expectations on a target with a snapshot flow. The owner chose
a seed table and a second `AUTO CDC` flow (2026-11-04). These tasks supersede T023's members
flow and run before T026. In T027, read 941,236 passed for the expectations, and ignore the
stop condition about the snapshot.

- [X] T030 Update `spec.md`, `plan.md`, `research.md` (Decision 8), `data-model.md`, the contract and `quickstart.md` to the seed table, per FR-007 and FR-008 (contradicts)
- [X] T031 **Superseded by T034: never run, and the script was deleted.** Create `explorations/setup/04_dim_usuario_membros.sql`: an idempotent load of the two members into `workspace.gold.ref_dim_usuario_membros` with `quality` = `gold`. Run it twice and confirm 2 rows with an unchanged `data_carga`, per FR-007 and Principle I (missing)
- [X] T032 **Done, then superseded by T034.** In `src/pipeline/03_gold/02_dim_usuario.sql`, replace the snapshot flow, per FR-007 and FR-008 (contradicts)
  ```sql
  CREATE FLOW gold_dim_usuario_membros_flow AS AUTO CDC INTO workspace.gold.dim_usuario
  FROM STREAM(workspace.gold.ref_dim_usuario_membros)
  KEYS (usuario_uuid)
  SEQUENCE BY data_carga
  STORED AS SCD TYPE 1;
  ```

## Phase 11: No expectations, members in the view

Owner direction, 2026-11-04, after constitution v2.0.0. These tasks supersede T023's
expectations, T031 and T032.

- [X] T033 Remove both expectations from `src/pipeline/03_gold/02_dim_usuario.sql`, and restate FR-008, per owner direction 2026-11-04 and Constitution III (contradicts)
- [X] T034 Delete `explorations/setup/04_dim_usuario_membros.sql` and `gold_dim_usuario_membros_flow`, per owner direction 2026-11-04 (unrequested)
- [X] T035 Add the two members to `vw_gold_dim_usuario_tb_usuario`: `UNION ALL` first, and if rejected, generated from the silver stream inside the view, per FR-007 and owner direction 2026-11-04 (missing)

## Implementation notes, Phase 9

### 2026-11-04

**T020**: spec, plan, research, data model, contract and quickstart updated.

**T021**: 941,234 rows, 941,234 keys, 941,234 distinct masked keys (no collision); 0 null
sequence values; silver's `data_carga` is `timestamp`, from 2026-10-28T21:11:13Z to
21:11:28Z; smallest masked key 3,252,875,404,337.

**T022–T024**: the two files written and `01_dim_usuario.sql` deleted. No forbidden token;
the target, the view (without `data_carga_silver`) and both member rows list the 11 columns
in order.

**T025**: the owner approved the drop. The old workspace file was deleted, the two new
files uploaded and identical to the repository, and the materialized view dropped.
`workspace.gold` holds `dim_tempo` only until an update succeeds.

**T026, blocked**: dry run `e7a215fc-34d2-4c01-a0f9-cac8638a6770` **FAILED** with
`APPLY_CHANGES_FROM_SNAPSHOT_EXPECTATIONS_NOT_SUPPORTED`: a target with a snapshot flow
cannot declare expectations, which conflicts with FR-008 and Principle III. Stopped for the
owner's decision, as T026 requires.

**T033–T035, T030 revised**: expectations, seed script and second flow removed; docs updated
to match. The seed script never ran, so `ref_dim_usuario_membros` never existed.

**T035**: `UNION ALL`: dry run `d14aaf4f` **COMPLETED**, but update `771c5ad8` **FAILED** with
`Union between streaming and batch DataFrames/Datasets is not supported`. A dry run does not
catch this. The owner's fallback was applied: each silver row emits the user and the two
members.

**T026**: dry run `31ad0aa3` **COMPLETED**, update `bd1e072d-5256-45bc-8463-d876803fcdb9`
**COMPLETED**. Updates in the window, all `API_CALL`, none a full refresh: `e7a215fc`,
`d14aaf4f` and `31ad0aa3` (dry runs); `771c5ad8` (failed), `bd1e072d` and `1e97c6db`.

**T027**: `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `membros` 2 (`sk_usuario < 0`);
`api` 741,234; `arquivo` 200,000; `divergentes` 0; `sem_dimensao` 4,362. `-1` / `'-1'` with
every text attribute `Desconhecido`, `-2` / `'-2'` with `Não se aplica`, age empty in both.
The 11 columns in order, no system column visible; `quality` = `gold`; `STREAMING_TABLE`.
Expectations: none to record (T033). Second update `1e97c6db-6720-494b-b5c9-d3357e80c155`, no
new data: the seven sample rows and a checksum over all 941,236 rows of `sk_usuario`,
`usuario_uuid` and `data_carga` are identical; `data_carga` is 2026-11-04T19:08:37.843Z on
every row. Flow row metrics came back empty, so the 2.8 million rows the view emits follow
from its definition and were not measured. **Not exercised**: the overwrite path of FR-004
and members' `data_carga` when new silver rows arrive (no repeated key, generators must not
run), and key stability across a full refresh (not run; needs the owner's approval).

**T028**: `doc/pipeline-reference.md`, `doc/architecture.md`, `doc/README.md`,
`doc/known-issues.md`.

**T029**: the workspace copy is identical to the repository. Silver and bronze files are
unchanged; `bronze.dados_database` still holds the three inserts; `silver.tb_usuario` 941,234.
Uncommitted, including the constitution amendment, whose Sync Impact Report must be removed
before committing.

---

## Phase 12: Convergence

Owner direction, 2026-11-04: make feature 009 simpler. `AUTO CDC` stays, and these tasks
supersede the members in the view of T035. The conventions at the top of this file still
apply. The snapshot flow was rejected in T026 only because the target had expectations,
which T033 removed.

- [X] T036 Rewrite `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/gold-dim-usuario.md` and `quickstart.md` for the final design only, per owner direction 2026-11-04 and FR-007 (contradicts)
  - `spec.md`: record the members' snapshot flow in the 2026-11-04 clarifications, and remove the "Silver is empty" edge case and the assumption that members appear with the first silver row.
  - `plan.md`, `data-model.md`, the contract: one plain view, one streaming table, two flows; replace the explode notes and the about 2.8 million rows.
  - `research.md`: reduce Decision 8 to the decision, why `WITH VERSION` must stay, and one line for each rejected attempt, including the `UNION ALL` a dry run did not catch.
  - `quickstart.md`: remove the one-time steps that are already done (deleting the old file, approving the drop).
- [X] T037 Replace `src/pipeline/03_gold/01_vw_gold_dim_usuario_tb_usuario.sql` with a plain view and a short Portuguese header comment, per owner direction 2026-11-04 (contradicts)
  ```sql
  CREATE TEMPORARY VIEW vw_gold_dim_usuario_tb_usuario
  COMMENT '<Portuguese>'
  AS
  SELECT
    xxhash64(usuario_uuid) & 9223372036854775807 AS sk_usuario,
    usuario_uuid, nome_usuario, email_usuario, idade_usuario, sexo_usuario,
    estado_usuario, profissao_usuario, empresa_usuario, origem,
    current_timestamp() AS data_carga,
    data_carga          AS data_carga_silver
  FROM STREAM(workspace.silver.tb_usuario);
  ```
- [X] T038 In `src/pipeline/03_gold/02_dim_usuario.sql`, remove the column list, shorten the header comment, keep the users flow unchanged, and add the members flow, per FR-007 (partial)
  ```sql
  CREATE FLOW gold_dim_usuario_membros_flow AS AUTO CDC ONCE INTO workspace.gold.dim_usuario
  FROM SNAPSHOT (
    SELECT CAST(-1 AS BIGINT) AS sk_usuario, '-1' AS usuario_uuid,
           'Desconhecido' AS nome_usuario, 'Desconhecido' AS email_usuario,
           CAST(NULL AS INT) AS idade_usuario, 'Desconhecido' AS sexo_usuario,
           'Desconhecido' AS estado_usuario, 'Desconhecido' AS profissao_usuario,
           'Desconhecido' AS empresa_usuario, 'Desconhecido' AS origem,
           current_timestamp() AS data_carga
    UNION ALL
    SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica', CAST(NULL AS INT),
           'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica',
           'Não se aplica', current_timestamp()
  )
  WITH VERSION (
    SELECT TIMESTAMP'1900-01-01' AS versao
    WHERE NOT EXISTS (SELECT 1 FROM last_snapshot_version())
  )
  KEYS (usuario_uuid)
  STORED AS SCD TYPE 1;
  ```
  **Keep `WITH VERSION`.** A snapshot treats absent keys as deleted at its version, and the 1900 version keeps it older than every silver row.
- [X] T039 **Ask the owner to approve a full refresh of `workspace.gold.dim_usuario` only, and do not continue without it**, per FR-005 and Constitution, Development Workflow: full refresh (partial)
  - Before uploading, save `SELECT count(*), sum(hash(usuario_uuid, sk_usuario)) FROM workspace.gold.dim_usuario`.
  - Upload `src/pipeline` and confirm the workspace copy is identical to the repository.
  - Following the quota conventions, dry run, then run an update with `--json` and `full_refresh_selection` limited to this table. Never use `--full-refresh`, which resets every table. A completed dry run proves little here, so only the real update counts.
  - **If the update fails, stop and ask the owner.** The previous version is in commit `9b0bd91`.
- [X] T040 Run `quickstart.md` and record the results, per FR-005, FR-007, SC-001 to SC-006 and US1 to US3 (partial)
  - `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `membros` 2; `api` 741,234; `arquivo` 200,000; `divergentes` 0; `sem_dimensao` 4,362. **If `linhas` is near 2, the snapshot deleted the users: stop and ask the owner.**
  - The checksum saved in T039 is unchanged, which proves the keys survive a full refresh. `data_carga` is expected to be newer.
  - The 11 columns are in the order of FR-002, with `data_carga_silver` absent. If the order differs, restore the column list in the target and report it.
  - Run a second update with no new data: every key, `data_carga` and the row count are unchanged, and the members flow stays idle.
  - Confirm silver and bronze are unchanged. Record that FR-004's overwrite path is still not exercised, because the generators must not run.
- [X] T041 Update `doc/pipeline-reference.md`, `doc/README.md`, `doc/architecture.md` and `doc/known-issues.md`: describe the plain view and the members' snapshot flow, remove the three-row explanation, and remove the known issue about members while silver is empty, per FR-012 (partial)

## Implementation notes, Phase 12

### 2026-11-04

**T036–T038**: docs rewritten; the view is a plain `SELECT`; the target has no column list and
two flows. No forbidden token.

**T039**: the owner approved a full refresh of `dim_usuario` only. Saved 941,236 rows and key
checksum 197693239602. Dry run `dd10c4f0` **COMPLETED**; update
`2bd328d8-712c-425a-a2f7-72ef9f41e837` **COMPLETED**, with `full_refresh_selection` =
`workspace.gold.dim_usuario` and every other dataset `EXCLUDED`.

**T040**: `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `membros` 2; `api` 741,234;
`arquivo` 200,000; `divergentes` 0; `sem_dimensao` 4,362. The members are as in T011. The 11
columns are in the order of FR-002, so the column list was not needed; `quality` = `gold`;
`STREAMING_TABLE`. **The key checksum is identical after the full refresh** (FR-005). `data_carga`
has two values, one per flow: 20:20:48.774Z and 20:20:58.391Z. Update `{U2}`, no new data: a
checksum over all rows of `sk_usuario`, `usuario_uuid` and `data_carga` is identical, and the
members flow did not change the rows. Silver 941,234 and `bronze.dados_database` 3 unchanged.
**Not exercised**: FR-004's overwrite path, because silver has no repeated key and the
generators must not run.

**T041**: `doc/pipeline-reference.md`, `doc/README.md`, `doc/architecture.md`,
`doc/known-issues.md`.

---

## Phase 13: Inferred users (spec FR-013, 2026-11-05)

**Purpose**: give `dim_usuario` a row for every user that sales reference, so that
`fato_venda` can inner-join it (constitution v3.1.0, Principle V).

Design: plan "Revision 2026-11-05"; research, Decisions 10–13. Validation: quickstart
section 6.

**Independent Test**:
- `dim_usuario` has 945,598 rows, of which 4,362 are inferred;
- the anti join of `tb_venda` against `dim_usuario` returns 0 rows;
- silver users' keys and `data_carga` are unchanged.

**Phase conventions**:
- `WS=/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline`.
- Upload with `databricks workspace import-dir src/pipeline $WS --overwrite`.
- Verify each file with `databricks workspace export $WS/<path> --format AUTO | cmp - src/pipeline/<path>`.
- SQL runs through `databricks experimental aitools tools query`.
- No full refresh, no table drop, and no generator run. Comments are in Portuguese; docs in
  English.

- [X] T042 Record the baseline before any change:
  - the pipeline is `IDLE`;
  - quickstart 6 "Before the change": `linhas` 941,236 and `checksum` of `dim_usuario`;
    `faltantes` 4,362;
  - the same checksum restricted to
    `NOT (sk_usuario > 0 AND nome_usuario = 'Desconhecido') AND sk_usuario > 0`
    (silver users only);
  - `fato_venda`: 420,472 rows, `count_if(sk_usuario = -1)` 4,362 and
    `sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))`
    736219987002.
- [X] T043 Renumber the gold files (research, Decision 12). Use `git mv` for the five tracked
  files, from the highest number down:
  - `06_dim_curso.sql` → `07_`;
  - `05_vw_gold_dim_curso_membros.sql` → `06_`;
  - `04_vw_gold_dim_curso_dados_database.sql` → `05_`;
  - `03_dim_codigos.sql` → `04_`;
  - `02_dim_usuario.sql` → `03_`.

  Use plain `mv` for the untracked `07_fato_venda.sql` → `08_fato_venda.sql`. Contents are
  unchanged. Afterwards, `ls src/pipeline/03_gold` shows `01_`, `03_` to `08_`.
- [X] T044 [US1] Create `src/pipeline/03_gold/02_vw_gold_dim_usuario_tb_venda.sql`
  (research, Decisions 10 and 11).
  - **Header in Portuguese**:
    - "Camada gold: view do fluxo AUTO CDC de usuários inferidos de dim_usuario";
    - users that `silver.tb_venda` references and `silver.tb_usuario` does not hold (silver
      rejected them) get an inferred row: Kimball's inferred member, so that a fact's
      lookup always finds the user;
    - the key uses the same expression as the users view;
    - `Desconhecido` labels, `origem` from the sale;
    - sequence `1900-01-02`: newer than the members snapshot (1900-01-01), so a full
      refresh does not delete them, and older than any silver row, so a real row replaces
      the inferred one with the same key;
    - users seen only in accesses get no row (owner).
  - **Body**:

    ```sql
    CREATE TEMPORARY VIEW vw_gold_dim_usuario_tb_venda
    COMMENT 'Usuários que as vendas referenciam e silver.tb_usuario não tem (inferidos), no formato do fluxo AUTO CDC de dim_usuario.'
    AS
    SELECT
      xxhash64(v.usuario_uuid) & 9223372036854775807 AS sk_usuario,
      v.usuario_uuid,
      'Desconhecido' AS nome_usuario,
      'Desconhecido' AS email_usuario,
      CAST(NULL AS INT) AS idade_usuario,
      'Desconhecido' AS sexo_usuario,
      'Desconhecido' AS estado_usuario,
      'Desconhecido' AS profissao_usuario,
      'Desconhecido' AS empresa_usuario,
      v.origem,
      current_timestamp() AS data_carga,
      TIMESTAMP'1900-01-02' AS data_carga_silver
    FROM STREAM(workspace.silver.tb_venda) AS v
    LEFT JOIN workspace.silver.tb_usuario AS u
      ON u.usuario_uuid = v.usuario_uuid
    WHERE u.usuario_uuid IS NULL
      AND v.usuario_uuid IS NOT NULL
    ```

    The columns are in the order of `01_vw_gold_dim_usuario_tb_usuario.sql`.
- [X] T045 [US1] In `src/pipeline/03_gold/03_dim_usuario.sql`:
  - **Header**: add one line saying the dimension also receives inferred users from
    `vw_gold_dim_usuario_tb_venda`.
  - **New flow**, after the users flow and before the members flow, with a Portuguese
    comment ("Usuários inferidos: vendas cujo usuário silver não tem; uma linha real
    posterior substitui a inferida com a mesma chave"):

    ```sql
    CREATE FLOW gold_dim_usuario_tb_venda_flow AS AUTO CDC INTO workspace.gold.dim_usuario
    FROM STREAM(vw_gold_dim_usuario_tb_venda)
    KEYS (usuario_uuid)
    SEQUENCE BY data_carga_silver
    COLUMNS * EXCEPT (data_carga_silver)
    STORED AS SCD TYPE 1;
    ```

  - Change nothing else in the file.
- [X] T046 [US1] Switch the workspace over.
  - Delete the six old names: `databricks workspace delete $WS/03_gold/<name>` for
    `02_dim_usuario.sql`, `03_dim_codigos.sql`,
    `04_vw_gold_dim_curso_dados_database.sql`, `05_vw_gold_dim_curso_membros.sql`,
    `06_dim_curso.sql` and `07_fato_venda.sql`.
  - Upload `src/pipeline`.
  - Confirm `databricks workspace list $WS/03_gold` shows exactly `01_` to `08_`, each
    identical to the repository.
  - Run a dry run and expect `COMPLETED`.
  - On a rejection, restore the previous state: rename back, remove the view and the flow,
    re-upload, and confirm with a dry run. Then STOP and report to the owner.
- [X] T047 [US1] At least 4 minutes after the last update, run a **real** ordinary update
  and expect `COMPLETED` (the contract: a dry run is not proof). Record the update id. Then
  run the quickstart 6 "After the update" queries:
  - `linhas` 945,598, `chaves` 945,598, `inferidos` 4,362, `membros` 2;
  - `vendas_sem_usuario` 0;
  - `origem_errada` 0, `chave_errada` 0, `rotulo_errado` 0.

  **Stop condition**: if the update fails, rows are missing, or silver users changed, STOP,
  restore as in T046 and report. Never refresh.
- [X] T048 [US2] Key stability.
  - The silver-users checksum of T042 is unchanged.
  - At least 4 minutes after T047, run another ordinary update and expect `COMPLETED`. The
    full `dim_usuario` checksum and row count are unchanged from T047, and the new flow
    reads 0 new rows.
- [X] T049 [US1] Confirm `fato_venda` is unchanged by this phase: 420,472 rows,
  `sk_usuario = -1` for 4,362, and checksum 736219987002 (T042). Its keys are resolved
  once; switching it to inner joins is feature 013's revision.
- [X] T050 [P] In `doc/pipeline-reference.md`:
  - **`### dim_usuario`**:
    - the third flow `gold_dim_usuario_tb_venda_flow` and its view
      [02_vw_gold_dim_usuario_tb_venda.sql](../src/pipeline/03_gold/02_vw_gold_dim_usuario_tb_venda.sql);
    - the inferred-user rule (sales only, `Desconhecido` labels, `origem` from the sale,
      sequence 1900-01-02, replaced by a real row under the same key);
    - coverage: every sale's user has a row;
    - counts on the T047 date: 945,598 (941,234 silver + 4,362 inferred + 2 members).
  - **File links**: replace every old one, `02_dim_usuario.sql` → `03_dim_usuario.sql`,
    `03_dim_codigos.sql` → `04_`, `04_vw_gold_dim_curso_dados_database.sql` → `05_`,
    `05_vw_gold_dim_curso_membros.sql` → `06_`, `06_dim_curso.sql` → `07_` and
    `07_fato_venda.sql` → `08_`.
  - **`### fato_venda`**: add one sentence: "the 4,362 `-1` users now exist as inferred
    users in `dim_usuario`; existing sales keep `-1` until feature 013's revision".
- [X] T051 [P] In `doc/architecture.md`:
  - replace the same old file names in every link;
  - add [02_vw_gold_dim_usuario_tb_venda.sql](../src/pipeline/03_gold/02_vw_gold_dim_usuario_tb_venda.sql)
    to the "Deterministic surrogate key" row;
  - add a row "Inferred dimension members (Kimball) through a third `AUTO CDC` flow" pointing
    to it and to `03_dim_usuario.sql`;
  - in the mermaid graph, add `S4 --> G1`.
- [X] T052 [P] In `doc/README.md`:
  - **`03_gold/` layout**: renumber the lines, and add `02_vw_gold_dim_usuario_tb_venda.sql`
    ("Flow view: inferred users from sales").
  - **"Pipeline datasets"**: gold becomes "4 streaming views, 3 streaming tables and 1
    materialized view".
- [X] T053 [P] In `doc/known-issues.md`, replace any old gold file name. In the
  `obt_acesso` bullet, note that `dim_usuario` now covers every sale's user, but not users
  seen only in accesses.
- [X] T054 Final validation:
  - `grep -rn` for the six old names in `doc/` and `src/` finds nothing;
  - the workspace `03_gold` holds `01_` to `08_`, identical to the repository;
  - quickstart 6 "After the update" passes;
  - counts of `tb_usuario` (941,234), `tb_venda` (420,472), `dim_codigos` (62),
    `dim_curso` (5) and `fato_venda` (420,472) are unchanged;
  - the pipeline is `IDLE`;
  - stop the warehouse with `--no-wait`.
- [X] T055 Constitution review of `02_vw_gold_dim_usuario_tb_venda.sql` and
  `03_dim_usuario.sql`:
  - current syntax only;
  - `STREAM(` only on `tb_venda`; `tb_usuario` read static;
  - the key expression identical to `01_vw_gold_dim_usuario_tb_usuario.sql`;
  - three flows with identical `KEYS`;
  - no constraints, no `UNION`, no `CLUSTER BY` / `PARTITIONED BY`;
  - comments in Portuguese.

  Record the outcome, the update ids and the counts in "Implementation notes, Phase 13" at
  the end of this file.

### Phase 13 dependencies

- **Order**: T042 → T043 → T044 → T045 → T046 → T047 → T048, then T049.
- T050–T053 touch different files and can run in parallel after T047, because the counts
  are known by then.
- T054 runs after them; T055 runs last.
- Two updates, at least 4 minutes apart.

## Implementation notes, Phase 13

### 2026-11-06

**T042**: the pipeline was `IDLE`. Baseline:
- `dim_usuario`: 941,236 rows, checksum -482795858800;
- silver users only (941,234 rows, none named `Desconhecido`): checksum -484022488009;
- `faltantes`: 4,362;
- `fato_venda`: 420,472 rows, `sk_usuario = -1` for 4,362, checksum 736219987002.

**T043**: `git mv` for all six files, from the highest number down. All six were already
committed, including `07_fato_venda.sql`.

**T044–T045**: `02_vw_gold_dim_usuario_tb_venda.sql` was created, and
`gold_dim_usuario_tb_venda_flow` was added to `03_dim_usuario.sql`. The table's `COMMENT` was
left as it was, per T045 ("change nothing else"). It still says "um registro por usuário de
silver.tb_usuario"; a later edit can mention the inferred users.

**T046**: the six old names were deleted from the workspace and the files uploaded. `03_gold`
holds exactly `01_` to `08_`, each identical to the repository. Dry run `61f21765`
**COMPLETED**.

**T047**: real update `4d2eebb5-3b1c-4ed6-964f-50d3dd828b93` **COMPLETED** (ordinary). The
three-flow combination (users, inferred users, members snapshot; SCD type 1) is accepted.
- `linhas` 945,598, `chaves` 945,598, `inferidos` 4,362, `membros` 2.
- `vendas_sem_usuario` 0.
- `origem_errada` 0, `chave_errada` 0, `rotulo_errado` 0.
- Silver-users checksum -484022488009, unchanged from T042.

**T048**: update `5156d11d-413a-48b8-82c9-933ddc6b5d14` **COMPLETED**, with no change. The full
checksum -413324606090 and the 945,598 rows are identical to T047's.

**T049**: `fato_venda` is unchanged: 420,472 rows, `sk_usuario = -1` for 4,362, checksum
736219987002. Its keys are resolved once; feature 013's revision moves those sales to their
inferred users.

**T050–T053**: documentation updated.
- Every old file name is replaced in `doc/`.
- `pipeline-reference.md`: `dim_usuario` covers the third flow, the inferred-user rule, coverage
  and counts; `fato_venda` notes the 4,362.
- `architecture.md`: deterministic-key row, a new inferred-members row, and the graph edge
  `S4 --> G1`.
- `README.md`: layout and gold count (4 streaming views, 3 streaming tables, 1 materialized
  view).
- `known-issues.md`: the `obt_acesso` bullet.

**T054**: no old name remains in `doc/` or `src/`, and the workspace `03_gold` matches the
repository. Counts:

| Dataset | Rows |
|---|---|
| `tb_usuario` | 941,234 |
| `tb_venda` | 420,472 |
| `dim_codigos` | 62 |
| `dim_curso` | 5 |
| `fato_venda` | 420,472 |

`vendas_sem_usuario` is 0. The pipeline is `IDLE`; the warehouse is stopped.

**T055**: the view reads `STREAM(` only on `tb_venda` and `tb_usuario` as static, with no
`UNION` and no constraints.
- `03_dim_usuario.sql` has three flows, each with `KEYS (usuario_uuid)`. Its only `UNION` is the
  members snapshot's literal rows (unchanged).
- The key expression matches the users view, with the alias `v.` that the join requires.
- No full refresh, drop or generator run.

---

## Phase 14: Undo the inferred users (owner, 2026-11-06)

The owner decided that `dim_usuario` holds only the users silver delivers, plus the members
(spec, Clarifications 2026-11-06). Phase 13 is reverted, and the 4,362 placeholder rows are
cleared by a full refresh of `dim_usuario` only, which the owner approved.

- [X] T056 Record the baseline without inferred rows: 941,236 rows; checksum of every column
  except `data_carga` = 490186792805.
- [X] T057 Restore the repository to the committed state with
  `git restore --staged src/pipeline/03_gold doc` and `git restore src/pipeline/03_gold doc`,
  then delete the untracked new names. `src/pipeline/03_gold` holds `01_`–`07_` again;
  `02_dim_usuario.sql` has no inferred-users flow; the four docs are back to their committed
  text.
- [X] T058 In the workspace, delete `02_vw_gold_dim_usuario_tb_venda.sql` and the six renamed
  names `03_`–`08_`, then upload. `03_gold` holds exactly `01_`–`07_`, each identical to the
  repository.
- [X] T059 Run a dry run with `full_refresh_selection = ["workspace.gold.dim_usuario"]`: `485d2fb0`
  **COMPLETED**. Then run the update with the same selection: `8d27cdf5-e074-48da-9c74-50c762d19c51`
  **COMPLETED** (`full_refresh` false, so only `dim_usuario` was refreshed).
- [X] T060 Verify:
  - `dim_usuario` has 941,236 rows, 941,236 distinct keys, 0 inferred rows and 2 members;
  - the checksum without `data_carga` is 490186792805, equal to T056, so every key and
    attribute is unchanged;
  - 4,362 sales again have no user row (expected);
  - `tb_usuario` has 941,234 rows;
  - `fato_venda` is unchanged: 420,472 rows, checksum 736219987002, with `sk_usuario = -1` for
    4,362 through its left join;
  - the pipeline is `IDLE`; the warehouse is stopped.
- [X] T061 Record the reversal:
  - spec: a Clarifications bullet for 2026-11-06; FR-013 and the inferred-user entity removed;
    FR-003, SC-001, SC-006 and the edge case restored;
  - undo notes at the head of the 2026-11-05 sections of plan, research and quickstart;
  - data model and contract corrected.

`data_carga` of every `dim_usuario` row now carries the refresh time.
