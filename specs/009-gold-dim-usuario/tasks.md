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
