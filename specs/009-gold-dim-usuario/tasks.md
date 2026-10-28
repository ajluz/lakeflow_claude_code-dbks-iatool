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
- [ ] T008 Following the quota conventions, dry run (`--validate-only`) to `COMPLETED`, with `workspace.gold.dim_usuario` defined. Apply the allowed `QUALIFY` fallback if needed; report anything else
- [ ] T009 Following the quota conventions, run the update to `COMPLETED`, and record its `update_id` and every update created in the window

---

## Phase 7: Validation

- [ ] T010 [US1] Run quickstart.md step 3:
  - `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `api` 741,234; `arquivo` 200,000;
  - `divergentes` 0;
  - `sem_dimensao` 4,362 (users of sales that facts will resolve to `-1`);
  - the 11 columns of the data model, in order, `sk_usuario bigint`, `idade_usuario int`, `data_carga timestamp`;
  - `quality` = `gold`.
- [ ] T011 [US3] From quickstart.md step 3, the member rows: exactly one row with `sk_usuario` `-1` (`'-1'`, `Desconhecido`) and one with `-2` (`'-2'`, `Não se aplica`), `idade_usuario` null in both
- [ ] T012 Run quickstart.md step 4 for the update of T009: `check_sk_usuario` and `check_usuario_uuid` each passed 941,236, failed 0
- [ ] T013 Ask the owner to confirm that the Data quality tab of `dim_usuario` shows the two expectations. Record the answer
- [ ] T014 [US2] Run quickstart.md step 5: save the sample (the two members and five users), run a second update following the quota conventions (no new data), and confirm every `(usuario_uuid, sk_usuario)` pair is identical and `data_carga` is later

---

## Phase 8: Polish

- [ ] T015 [P] In `doc/pipeline-reference.md`, rewrite `### dim_usuario` as built: file `../src/pipeline/03_gold/01_dim_usuario.sql`, materialized view over `silver.tb_usuario`, grain one user, SCD type 1, `sk_usuario = xxhash64(usuario_uuid)` and why, the 11 columns, the two members, the two `FAIL UPDATE` expectations, the counts of T010; and add `dim_usuario` to the intro's "as built" list
- [ ] T016 [P] In `doc/architecture.md`, in the features table, replace the `01_dim_usuario.sql` link in "Explicit schema with identity surrogate keys" by removing it from that row, and add `../src/pipeline/03_gold/01_dim_usuario.sql` to the "Materialized views" row; add a row "Deterministic surrogate key (`xxhash64` of the business key) and default members" → the same file
- [ ] T017 [P] In `doc/README.md`, add `03_gold/` to the `src/pipeline/` layout with `01_dim_usuario.sql` ("User dimension: materialized view, stable hash surrogate key, unknown / not-applicable members"), turning the `02_silver/` branch into `├──` and its children's prefix into `│       │   `; change the dataset count's "gold not built yet" to "in gold, 1 materialized view (plus `dim_tempo`, created outside the pipeline)"
- [ ] T018 [P] In `doc/known-issues.md`, in the smaller item on identity surrogate keys, remove `dim_usuario` and state that it now uses a deterministic `xxhash64` key (feature 009) and that identity columns are not supported on materialized views (`databricks-pipelines` skill)
- [ ] T019 Final review:
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
