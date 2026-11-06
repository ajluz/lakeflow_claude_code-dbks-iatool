---

description: "Task list for feature 006-silver-tb-usuario"
---

# Tasks: Silver User Table from API Events and Partner Files

**Input**: Design documents from `/specs/006-silver-tb-usuario/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/silver-tb-usuario.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching step of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Note**: generated during `/speckit-implement`, because `/speckit-tasks` had not been
run for this feature.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Conventions for every task

- **Statement shapes**: exactly those of contracts/silver-tb-usuario.md, with a header
  comment in Portuguese in each file.
  - The three views of the files path and the API shaping view are `CREATE TEMPORARY VIEW`.
  - `10_tb_usuario.sql` holds the target with the three constraints and the two
    `AUTO CDC` flows.
- **Allowed fallback, and only this one**: if the dry run rejects constraints on a target
  without a column list, declare the 10 columns with their types (data-model.md) before
  the constraints. Report anything else to the owner.
- **Workspace**: `--profile databricks-free` on every command. The pipeline is
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.
- **Free Edition quota**: before each `start-update`:
  1. stop the warehouse (`databricks warehouses stop f796ffb64302b6ba`), but **never while
     queries are still running on it**;
  2. make sure the pipeline is `IDLE`;
  3. wait about 4 minutes after the previous update.
- **Never** refresh an existing table without the owner's explicit approval.
- **Why all definitions are complete before the first run**: a column added to a
  streaming table after rows were written is null on those rows.

---

## Phase 1: Setup

- [X] T001 Confirm the starting state, changing nothing:
  - the pipeline is `IDLE`;
  - `02_silver/` in the workspace lists `01_` to `05_` only;
  - `SHOW TABLES IN workspace.silver` does not list `tb_usuario`.

---

## Phase 2: Foundational

- [X] T002 Record the expected counts of quickstart.md step 1 in the Implementation notes. They were measured on 2026-10-18 (research.md): API 756,249 candidates and 741,234 kept, with 15,015 invalid sex and 30,190 invalid emails; files 200,000 keys, all kept, 0 invalid emails. Re-run the queries only if bronze changed since

---

## Phase 3: User Story 1 - Users from the site in one conformed table (Priority: P1) 🎯 MVP

**Goal**: API users from valid events reach `tb_usuario` with the reused `usuario_uuid` and `origem = 'API'`.

**Independent Test**: quickstart.md step 3. The `API` rows equal 741,234, and `api_sem_acesso` is explained by `tb_acesso`'s address rule.

- [X] T003 [P] [US1] Create `src/pipeline/02_silver/08_vw_silver_usuario_api.sql` with the contract's select list, from `STREAM(vw_silver_eventos_api)` with `WHERE usuario_uuid IS NOT NULL`. `empresa_usuario` is `CAST(NULL AS STRING)`. (no `sequencia` column after the revision)
- [X] T004 [US1] Create `src/pipeline/02_silver/10_tb_usuario.sql` exactly as in the contract:
  - the target with `check_sexo_usuario` (drop row), `check_email_usuario` (warn) and `check_usuario_uuid` (warn), plus `TBLPROPERTIES ("quality" = "silver")`;
  - `silver_tb_usuario_api_flow` and `silver_tb_usuario_arquivo_flow`, both `INSERT INTO workspace.silver.tb_usuario BY NAME SELECT * FROM STREAM(<shaping view>)`. (Revised by the owner on 2026-10-18; first written with `AUTO CDC` SCD type 1, see notes.)

  The header comment in Portuguese names the two sources and their append flows, says uniqueness is verified, and names the drop as a declared exclusion (constitution v1.7.0) and the informative email rule.

---

## Phase 4: User Story 2 - Employees of partner companies in the same table (Priority: P1)

**Goal**: employees from the sales files reach `tb_usuario` once per company and name, with their company and `origem = 'ARQUIVO'`.

**Independent Test**: quickstart.md step 3. The `ARQUIVO` rows equal 200,000, `com_empresa` = 200,000, and `chave_arquivo_divergente` = 0.

- [X] T005 [P] [US2] Create `src/pipeline/02_silver/06_vw_bronze_dados_files.sql`: `SELECT * EXCEPT (source_file_name, _rescued_data) FROM STREAM(workspace.bronze.dados_files)`, nothing else
- [X] T006 [P] [US2] Create `src/pipeline/02_silver/07_vw_silver_vendas_arquivo.sql`: every column of `STREAM(vw_bronze_dados_files)`, plus `md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''))) AS usuario_uuid`. The header comment says this is the single definition of the files user key, which later sales tables must reuse
- [X] T007 [P] [US2] Create `src/pipeline/02_silver/09_vw_silver_usuario_arquivo.sql`: the same 10 columns, in the same order and with the same types, as the API shaping view. Use `nome_funcionario`, `email_funcionario`, `try_cast(idade AS INT)`, `sexo`, `estado`, `profissao`, `nome_empresa`, `'ARQUIVO'` and `current_timestamp()`, from `STREAM(vw_silver_vendas_arquivo)`
- [X] T008 Review the five files against the contract:
  - the two shaping views list the same 10 column names, in the same order;
  - no `UNION`, `uuid()`, `rand()`, ` concat(`, `AUTO CDC`, `MATERIALIZED`, `CLUSTER` or `PARTITIONED`;
  - the API key is not recomputed;
  - the files key appears only in `07_`.

---

## Phase 5: Deploy (shared by all stories)

- [X] T009 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free`. Confirm that `02_silver/` lists ten `FILE`s, and that the five new copies are identical to the repository
- [X] T010 Following the quota conventions, dry run (`--validate-only`) to `COMPLETED`, with the four views and `tb_usuario` defined. Apply the allowed fallback if needed; report anything else
- [X] T011 Following the quota conventions, run the update to `COMPLETED` and record its `update_id`. If it fails after creating `tb_usuario` and a fix changes its columns, **stop and ask the owner** to approve a refresh of `workspace.silver.tb_usuario` only

---

## Phase 6: Validation of US1 and US2

- [X] T012 [US1] Run quickstart.md step 3 for the `API` rows:
  - `linhas` = 741,234;
  - `com_empresa` = 0;
  - `sexo_invalido` = 0, `sem_chave` = 0, `sem_data_carga` = 0;
  - `api_sem_acesso`: record it, and confirm it equals the API users whose access `tb_acesso` dropped for the impossible address.
- [X] T013 [US2] Run quickstart.md step 3 for the `ARQUIVO` rows:
  - `linhas` = 200,000 and `com_empresa` = 200,000;
  - `chave_arquivo_divergente` = 0;
  - across the whole table, `chaves_repetidas` = 0;
  - the column list is the 10 of the data model, in order;
  - `quality` = `silver`.

---

## Phase 7: User Story 3 - Reject impossible sex values and measure invalid emails (Priority: P1)

**Goal**: the sex rule drops its rows without quarantine; the email rule only counts.

**Independent Test**: quickstart.md step 4. `check_sexo_usuario` failed = 15,015, `check_email_usuario` failed = 30,190, and candidates = rows + dropped.

- [X] T014 [US3] Run the expectations query of feature 004's quickstart step 4 for the update of T011. For dataset `tb_usuario`:
  - `check_sexo_usuario` failed 15,015;
  - `check_email_usuario` failed 30,190;
  - `check_usuario_uuid` failed 0;
  - passed + failed = 956,249 for each rule.

  Reconcile: 956,249 candidates = 941,234 rows + 15,015 dropped. Confirm `tb_quarentena` is still 9,240.
- [ ] T015 [US3] Ask the owner to confirm that the Data quality tab of `tb_usuario` shows the three expectations. Record the answer

---

## Phase 8: Polish

- [X] T016 Following the quota conventions, run an update with no new data. Confirm that both `tb_usuario` flows write 0 rows and the counts are unchanged
- [X] T017 [P] In `doc/pipeline-reference.md`:
  - rewrite `### tb_usuario` as built: two `AUTO CDC` SCD type 1 flows, the 10 columns per source, both keys' business columns, the three expectations, and the declared exclusion with its count;
  - add `vw_bronze_dados_files`, `vw_silver_vendas_arquivo`, `vw_silver_usuario_api` and `vw_silver_usuario_arquivo` to `### Temporary views`, replacing the earlier `vw_bronze_dados_files` row;
  - add `tb_usuario` and the views to the intro's "as built" list.
- [X] T018 [P] In `doc/architecture.md`:
  - add nodes for the four views and route the files path `B2 --> V2 --> <vw_silver_vendas_arquivo> --> <vw_silver_usuario_arquivo> --> S3`, and the API path `V6 --> <vw_silver_usuario_api> --> S3`, replacing `T1 --> S3` and the old `B2 --> V2 --> S3`;
  - in the features table, point "Combining sources with `UNION ALL`" to nothing (remove it) and add "Two `AUTO CDC` flows (SCD type 1) into one table, as deduplication" → `10_tb_usuario.sql`.
- [X] T019 [P] In `doc/README.md`, list `06_`–`10_` in the `02_silver/` layout, and update the dataset count: in silver, 6 streaming views, 1 private streaming table and 3 streaming tables
- [X] T020 Final review:
  - the workspace copies are identical to the repository;
  - `git status` shows changes only in `src/pipeline/02_silver/`, `doc/` and `specs/006-silver-tb-usuario/`;
  - features 004 and 005's files are unchanged.

  Complete the Implementation notes.

---

## Dependencies & Execution Order

- Setup → Foundational → definitions (US1 T003–T004, US2 T005–T007, review T008) →
  Deploy (T009–T011) → validations (T012–T015) → Polish (T016–T020)
- US1 and US2 share `10_tb_usuario.sql`, which holds both flows. The target needs both
  shaping views, so the stories are deployed together and validated separately.
- Parallel: T003, T005, T006 and T007 (separate files); T017, T018 and T019 (separate
  docs).

## Implementation Strategy

One deploy for all stories, because each Free Edition update costs a quota cycle, and the
target with both flows is one file. MVP = US1 validated (T012). US2 and US3 are then
proven on the same deployed definition.

## Implementation notes

### 2026-10-18

**T001–T002**: pipeline `IDLE`; `02_silver/` held `01_`–`05_`. Expected counts from
research.md (bronze unchanged since): API 756,249 candidates, 741,234 kept, 15,015
invalid sex, 30,190 invalid emails; files 200,000 keys, all kept.

**T003–T009**: five files written and reviewed. Both shaping views had the same columns,
no forbidden token was found, and the files key appears only in `07_`. The upload was
identical to the repository.

**T010–T011, first design**: dry run `1577db70-...` **COMPLETED**, then update
`e89d459d-...` **COMPLETED**, with `tb_usuario` as an `AUTO CDC` SCD type 1 target.
The constraints on a target without a column list were accepted.

**Owner's revision** (about 16:37 UTC): the owner asked why `AUTO CDC` was used when no
SCD is needed, and proposed append flows. Answer given: `AUTO CDC` was only for
deduplication. Today's data has no repeated key, so append flows give the same rows, more
simply, without the delete-condition deviation. The cost is that a future re-delivered
employee would be appended rather than merged. The owner chose append flows and approved
a refresh of `workspace.silver.tb_usuario` only. `08_` and `09_` lost `sequencia`, and
`10_` now has two `INSERT INTO ... BY NAME` flows. The spec (US2 scenario 2, edge case,
FR-007, SC-002, Assumptions), research (Decisions 1–2), data model, contract, quickstart,
plan (no deviation left), and the three docs were updated. The owner's snippet used
`STREAMING LIVE TABLE`, which is legacy syntax forbidden by Principle II; the code uses
`STREAMING TABLE`.

**Refresh `58a9d2f8-cbf2-405c-a8a9-1f8e35cee88f`** (owner-approved, `tb_usuario` only,
append flows): **COMPLETED**. It stands in for T010–T011 of the revised design.

**T012** (API): 741,234 rows; `com_empresa` 0; `sexo_invalido`, `sem_chave`,
`sem_data_carga` and `sem_idade` are 0. `api_sem_acesso` = 7,525. This equals the valid
API users with valid sex whose event had the impossible address, so those users exist but
`tb_acesso` dropped their access.

**T013** (ARQUIVO): 200,000 rows; `com_empresa` 200,000; `chave_arquivo_divergente` 0.
Whole table: 941,234 rows, `chaves_repetidas` 0. Columns: `usuario_uuid, nome_usuario,
email_usuario, idade_usuario, sexo_usuario, estado_usuario, profissao_usuario,
empresa_usuario, origem, data_carga`. `quality` = `silver`.

**T014**: flows `silver_tb_usuario_api_flow` wrote 741,234 rows and
`silver_tb_usuario_arquivo_flow` wrote 200,000. Expectations:

| flow | rule | passed | failed |
|---|---|---|---|
| api | `check_sexo_usuario` | 741,234 | 15,015 |
| api | `check_email_usuario` | 726,059 | 30,190 |
| api | `check_usuario_uuid` | 756,249 | 0 |
| arquivo | all three | 200,000 | 0 |

Reconciliation: 956,249 candidates = 941,234 rows + 15,015 dropped. `tb_quarentena` is
still 9,240. The table holds 29,599 invalid emails, 591 fewer than the rule's 30,190,
because those 591 rows were dropped for sex. Every expectation counts all incoming rows
(feature 005's finding).

**Finding (open, owner)**: unqualified flow names take the pipeline's default schema.
The event log names the flows `workspace.bronze.silver_tb_usuario_api_flow` and
`workspace.bronze.silver_tb_usuario_arquivo_flow`. The data is correct. Renaming an append
flow restarts it from the beginning and would duplicate every row, so a fix (qualified
flow names, or default schema `silver` in the pipeline settings) needs a refresh of
`tb_usuario` and the owner's approval. Not changed.

**Restructure for constitution v1.8.0** (owner, 2026-10-18, about 16:55 UTC): the owner
asked why so many views existed, and whether `doc/lakeflow_architecture.png` had been
considered. It had not been. The owner chose "match the diagram" and the constitution was
amended to v1.8.0 ("one expression per key"; the diagram is the target graph). Changes:
- removed `04_vw_silver_eventos_api.sql`, `07_vw_silver_vendas_arquivo.sql`,
  `08_vw_silver_usuario_api.sql` and `09_vw_silver_usuario_arquivo.sql`;
- renumbered `02_silver/` to `01_vw_bronze_dados_api`, `02_vw_bronze_dados_files`,
  `03_temp_tb_validacao_api`, `04_tb_quarentena`, `05_tb_acesso`, `06_tb_usuario`;
- `tb_acesso` and `tb_usuario` now read `temp_tb_validacao_api` and
  `vw_bronze_dados_files` directly and compute their keys inline, with the API
  `usuario_uuid` expression identical in both files.

The task texts above keep the names that were current when they ran. The data model,
contract, quickstart, research and plan were revised.

**Flow views (constitution v1.9.0, owner, 2026-10-18, about 16:57 UTC)**: the owner
asked that every append flow read a view that holds its whole query, so that the pipeline
is simpler to read. The constitution was amended to v1.9.0 (Principle V, "Flow views"),
with an exception to the target-graph rule for these views. The not-yet-run deploy of the
v1.8.0 restructure was stopped before its dry run. New layout:
- `06_vw_silver_tb_usuario_api.sql`: valid API events with a user, in the 10 columns;
  `usuario_uuid` uses the same expression as `tb_acesso`;
- `07_vw_silver_tb_usuario_files.sql`: `vw_bronze_dados_files` in the 10 columns;
- `08_tb_usuario.sql`: the target and two flows, `silver_tb_usuario_api_flow` and
  `silver_tb_usuario_files_flow` (renamed from `_arquivo_` to match the diagram's
  `_files`), each `SELECT * FROM STREAM(<view>)`.

These are the same two per-source views removed in the v1.8.0 restructure, now required
by the constitution and named by its convention.

**Deploy of v1.8.0 + v1.9.0** (owner-approved refresh of `tb_acesso` and `tb_usuario`
only): dry run `be92b95a-...` **COMPLETED**; refresh `ac8f733d-...` **COMPLETED**.
Results equal the pre-restructure numbers:
- `tb_acesso`: 2,516,192 rows (`Mobile` 1,262,684, `Computador` 1,136,377, `unknown`
  117,131), 0 impossible addresses, 0 repeated or empty keys.
- `tb_usuario`: API 741,234, `ARQUIVO` 200,000 (all with company), 0 invalid sex, 0
  repeated keys.
- Expectations: `tb_acesso` 25,523 / 118,305 / 0 / 0; `tb_usuario` API 15,015 sex, 30,190
  email, files 0.
- `api_sem_acesso` = 7,525 (users whose access had the impossible address);
  `sem_catalogo` = 0; `tb_quarentena` still 9,240.
- **New check (one expression per key, v1.8.0)**: 14,862 distinct `usuario_uuid` in
  `tb_acesso` have no row in `tb_usuario`. These are the sex-`X` users: `tb_usuario` drops
  them, but `tb_acesso`'s rules do not look at sex, so their accesses stay. 15,015 `X` users
  minus those whose access was also dropped for the address gives 14,862. The key
  expressions agree.
- The flows still appear as `workspace.bronze.silver_tb_usuario_*_flow` (open finding).

**T016** (on the restructured graph): update `0ea40874-d386-4be1-a6bc-06dd5e3c8dc4` (no
new data) **COMPLETED**. No flow wrote rows. `tb_acesso` 2,516,192, `tb_usuario` 941,234
and `tb_quarentena` 9,240 are unchanged.

**T020**: the eight `02_silver` workspace files are identical to the repository, and no
obsolete file remains. The earlier features' bronze files and the pipeline settings are
unchanged.

**AI tools (constitution v1.10.0, owner, 2026-10-25, about 18:50 UTC)**: the owner
asked whether the constitution considered the Databricks AI tools for development. It did
not: its only AI-adjacent references were to the `databricks-pipelines` skill, which is an
editor skill, not a Databricks product. The owner asked for it to be added. The
constitution was amended to v1.10.0 (Platform and Technology Constraints, "AI tools";
Development Workflow and Quality Gates, AI output is a draft):
- Databricks Assistant may write, explain and debug pipeline SQL; its output is reviewed
  against the constitution before commit, with legacy syntax, bare `WHERE` filters and
  divergent hash key expressions rewritten first;
- Genie is read-only; a Genie Agent for this project is defined over `workspace.gold`
  only, and when a Genie answer backs a quality gate its generated SQL is the evidence;
- AI Functions (`ai_*`) are not used in bronze, silver or gold datasets, because a model
  call is not deterministic (hash keys, reconciliation); they are allowed under
  `explorations/`, and a pipeline use needs an amendment naming the dataset and function;
- Agent Bricks are consumers of gold, like a dashboard, never part of the pipeline;
- every tool is optional: the pipeline validates, runs and reconciles without any of
  them, so Free Edition stays supported.

No file in `src/` or `explorations/` uses an AI tool, so nothing in this feature changes.
The strict AI Functions rule is the owner's call to relax, by an amendment naming the
dataset, if a demonstration wants `ai_classify` or `ai_extract` inside silver.

**Open (owner)**:
- T015: the Data quality tab of `tb_usuario`.
- The flow-name finding.
- Commit the constitution v1.6.0–v1.10.0 amendments (remove the Sync Impact Report first).

## Phase 9: Convergence

Owner request, 2026-11-06: `check_sexo_usuario` stops removing rows and only records the
error ("just comment it out on the code - on violation drop row"). Then both flow views set
the sex to empty (NULL) when it is not `M` or `F`. The rule keeps its predicate, so it
still counts those rows as failures, which is the informative record the owner asked for.

- [X] T021 In `src/pipeline/02_silver/08_tb_usuario.sql` line 12, comment out the action and keep the expectation: `CONSTRAINT check_sexo_usuario  EXPECT (sexo_usuario IS NOT NULL AND sexo_usuario IN ('M', 'F')), -- ON VIOLATION DROP ROW`. The comma stays before the comment. Rewrite the header lines 6–8 in Portuguese: `check_sexo_usuario` is now informative (owner, 2026-11-06; the `ON VIOLATION DROP ROW` is kept commented out to show the change), the views put the sex as NULL when it is not `M` or `F`, and the rule counts those rows. `check_email_usuario` still only measures. Nothing else in the file changes per owner request 2026-11-06 (contradicts)
- [X] T022 [P] In `src/pipeline/02_silver/06_vw_silver_tb_usuario_api.sql`, replace `payload.info_usuario.sexo AS sexo_usuario` with `CASE WHEN payload.info_usuario.sexo IN ('M', 'F') THEN payload.info_usuario.sexo END AS sexo_usuario`. Add a header line in Portuguese saying that a sex other than `M` or `F` becomes NULL. Columns, order and types are unchanged per owner request 2026-11-06 (missing)
- [X] T023 [P] In `src/pipeline/02_silver/07_vw_silver_tb_usuario_files.sql`, replace `sexo AS sexo_usuario` with `CASE WHEN sexo IN ('M', 'F') THEN sexo END AS sexo_usuario`, with the same header line as T022 per owner request 2026-11-06 (missing)
- [ ] T024 **Stop and ask the owner** before deploying. Changing the code affects new rows only (FR-013). The 15,015 users already dropped come back only through a full refresh of `workspace.silver.tb_usuario`. That refresh rewrites the source of `dim_usuario`'s stream, so `workspace.gold.dim_usuario` needs a full refresh too. `fato_venda` set its keys once, so its 4,362 sales with `sk_usuario = -1` keep that key unless `workspace.gold.fato_venda` is also fully refreshed. Ask which to approve: (a) no refresh, so only new users are affected; (b) `tb_usuario` + `dim_usuario`; (c) `tb_usuario` + `dim_usuario` + `fato_venda`. Use `full_refresh_selection` with exactly the approved tables, never a full pipeline refresh. Record the answer in the Implementation notes per FR-013, Constitution workflow (full refresh needs approval) (partial)
- [ ] T025 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` and confirm the three changed files are identical in the workspace. Following the quota conventions, run a dry run (`--validate-only`) to `COMPLETED`, then the update chosen in T024 to `COMPLETED`, and record its `update_id` per owner request 2026-11-06 (partial)
- [ ] T026 Validate against the update of T025, with `--profile databricks-free`:
  - in the expectations of `tb_usuario`, `check_sexo_usuario` has failures but drops no rows: the dropped count is 0, and passed + failed = rows written;
  - `SELECT sexo_usuario, count(*) FROM workspace.silver.tb_usuario GROUP BY ALL` shows only `M`, `F` and NULL;
  - with refresh (b) or (c): `tb_usuario` = 956,249 rows (941,234 + 15,015), the NULL sex count = 15,015, `usuario_uuid` is unique and never empty, and `dim_usuario` = 956,251 (2 members included);
  - with refresh (c): `fato_venda` = `silver.tb_venda` rows, the sums of `valor_pago` and `valor_desconto` equal silver's, and `count_if(sk_usuario = -1) = 0`;
  - `tb_quarentena` (9,240) and `tb_acesso` are unchanged;
  - re-measure first if bronze changed since 2026-11-06, per SC-003, SC-004, SC-007 (partial)
- [ ] T027 Record the owner's decision in this feature's documents, with no contradictory text left:
  - in `spec.md`: rewrite FR-008 (the rule only counts; the sex is NULL when not `M`/`F`) and FR-009 (no declared exclusion any more); update US3 and its scenarios, and SC-001, SC-002 and SC-003 (sex is `M`, `F` or empty; no row removed); replace the "Drop the row" Assumption; add a `### Session 2026-11-06` clarification;
  - in `plan.md`: add a "Revision 2026-11-06" section at the top;
  - in `data-model.md`, `contracts/silver-tb-usuario.md` and `quickstart.md`: the expected counts of T026;
  - per FR-008, FR-009, US3, SC-001–SC-003 (contradicts)
- [ ] T028 [P] Update the project documentation per FR-015 (contradicts):
  - `doc/pipeline-reference.md` line 204: `check_sexo_usuario` becomes "warn only; the views put the sex as NULL when not `M`/`F`";
  - `doc/pipeline-reference.md` line 209: remove the reconciliation exclusion;
  - `doc/data-generation.md` line 49: `X` becomes "kept in `tb_usuario` with an empty sex";
  - `specs/013-gold-fato-venda` (data-model, quickstart, contract, research Decision 9) and `specs/009-gold-dim-usuario`: replace the "4,362 sales whose user silver rejects" explanation with the counts T026 measured;
  - `doc/known-issues.md`: update any entry that mentions the dropped users.
- [ ] T029 Ask the owner to confirm that the Data quality tab of `tb_usuario` shows the three expectations, with `check_sexo_usuario` reporting failures and no dropped rows. Record the answer; it also closes T015 per T015, US3 (partial)
