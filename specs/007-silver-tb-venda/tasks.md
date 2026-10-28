---

description: "Task list for feature 007-silver-tb-venda"
---

# Tasks: Silver Sales Table from API Events and Partner Files

**Input**: Design documents from `/specs/007-silver-tb-venda/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/silver-tb-venda.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with validation tasks that
run the matching step of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Conventions for every task

- **Statement shapes**: exactly those of contracts/silver-tb-venda.md, with a header
  comment in Portuguese in each file. The two flow views are `CREATE TEMPORARY VIEW`;
  `11_tb_venda.sql` holds the target with the five constraints and the two append flows.
- **Column order**, in both flow views and in the table: `venda_uuid`, `data_venda`,
  `acesso_uuid`, `usuario_uuid`, `curso_uuid`, `forma_pagamento`,
  `quantidade_parcelas`, `valor_parcelas`, `valor_pago`, `percentual_desconto`,
  `valor_desconto`, `origem`, `data_carga`. Types as in data-model.md.
- **Helpers stay out of the table.** `preco` (list price) and `fracao` (discount
  fraction) are computed in an inner query and never selected by the outer query. A
  lateral column alias can only refer to an alias on its left, so any column that a
  later column reuses out of order (`valor_desconto` in the files view) is computed in
  the inner query.
- **Allowed fallbacks, and only these**:
  - research Decision 6: if quickstart step 1 shows `valor_parcela` in the payload, read
    that name;
  - research Decision 4: if quickstart step 1 shows repeated API sale keys, add
    `coalesce(payload.info_usuario.nome, '')` as the fifth component of the API
    `venda_uuid`.

  Record either in the Implementation notes, research.md and data-model.md. Report
  anything else to the owner.
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
  - `databricks current-user me --profile databricks-free` succeeds. If it reports an
    invalid refresh token, **stop and ask the owner** to run
    `databricks auth login --profile databricks-free` (the login expired on 2026-10-28);
  - the pipeline is `IDLE`;
  - `02_silver/` in the workspace lists `01_` to `08_` only;
  - `SHOW TABLES IN workspace.silver` does not list `tb_venda`.

---

## Phase 2: Foundational

- [X] T002 Run quickstart.md step 1 and record every number in the Implementation notes:
  the payload's type, `api_vendas`, `sem_desconto`, `acesso_descartado`,
  `usuario_descartado`, `parcelas_divergentes`, the API `chaves_venda_repetidas`,
  `arquivo_vendas` and the files `chaves_venda_repetidas`. Decide the two allowed
  fallbacks from them before any file is written. Report `parcelas_divergentes` to the
  owner with no change (research Decision 7)

---

## Phase 3: User Story 1 - Site sales in one conformed table (Priority: P1) 🎯 MVP

**Goal**: valid API events with a payment reach `tb_venda` with keys that join
`tb_acesso`, `tb_usuario` and the course catalog, and `origem = 'API'`.

**Independent Test**: quickstart.md step 3. The `API` rows equal `api_vendas`,
`com_acesso` equals the rows, and `api_sem_acesso` equals `acesso_descartado`.

- [X] T003 [P] [US1] Create `src/pipeline/02_silver/09_vw_silver_tb_venda_api.sql`, `CREATE TEMPORARY VIEW vw_silver_tb_venda_api`:
  - **inner query** `FROM STREAM(workspace.silver.temp_tb_validacao_api) WHERE NOT fl_registro_invalido AND payload.info_pagamento IS NOT NULL`, selecting `payload` and, copied character for character from `src/pipeline/02_silver/05_tb_acesso.sql`, the definitions of `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso`, `acesso_uuid`, `usuario_uuid` and `curso_uuid`. It also defines:
    - `preco`: `try_cast(replace(regexp_replace(payload.info_produto.valor, '[^0-9,]', ''), ',', '.') AS DECIMAL(9,2))`;
    - `fracao`: `CAST(coalesce(payload.info_pagamento.disconto, 0) AS DECIMAL(5,2))`;
    - `valor_desconto`: `CAST(preco * fracao AS DECIMAL(9,2))`.
  - **outer query**, the 13 columns in the conventions' order:
    - `venda_uuid`: `md5(concat_ws('||', coalesce(cast(timestamp_acesso AS STRING), ''), coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, ''), coalesce(payload.info_produto.product_name, '')))`, plus the Decision 4 fallback if T002 required it;
    - `timestamp_acesso AS data_venda`;
    - `acesso_uuid`, `usuario_uuid`, `curso_uuid` as computed;
    - `payload.info_pagamento.forma_pagamento AS forma_pagamento`;
    - `try_cast(payload.info_pagamento.quantidade_parcelas AS INT) AS quantidade_parcelas`;
    - `CAST(payload.info_pagamento.valor_parcelas AS DECIMAL(9,2)) AS valor_parcelas` (or `valor_parcela`, per T002);
    - `CAST(quantidade_parcelas * valor_parcelas AS DECIMAL(9,2)) AS valor_pago`;
    - `concat(CAST(fracao * 100 AS INT), '%') AS percentual_desconto`;
    - `valor_desconto`, `'API' AS origem`, `current_timestamp() AS data_carga`.

  The header comment in Portuguese says the view reads only valid events with a payment, and that the three reused keys are written as in `05_tb_acesso.sql`.
- [X] T004 [US1] Create `src/pipeline/02_silver/11_tb_venda.sql` exactly as in the contract:
  - the target `workspace.silver.tb_venda` with `check_venda_uuid` (`venda_uuid IS NOT NULL`), `check_usuario_uuid` (`usuario_uuid IS NOT NULL`), `check_curso_uuid` (`curso_uuid IS NOT NULL`), `check_data_venda` (`data_venda IS NOT NULL`) and `check_valor_pago` (`valor_pago IS NOT NULL AND valor_pago > 0`), all warn, plus `TBLPROPERTIES ("quality" = "silver")`;
  - `silver_tb_venda_api_flow` and `silver_tb_venda_files_flow`, both `INSERT INTO workspace.silver.tb_venda BY NAME SELECT * FROM STREAM(<flow view>)`.

  The header comment in Portuguese names the two sources and their append flows, says that no rule drops rows, that `acesso_uuid` is empty for corporate sales, and that uniqueness of `venda_uuid` is verified after each load.

---

## Phase 4: User Story 2 - Partner company sales in the same table (Priority: P1)

**Goal**: every sales file row reaches `tb_venda` with no access key, `pix`, one
installment, a user key that joins `tb_usuario`, and `origem = 'ARQUIVO'`.

**Independent Test**: quickstart.md step 3. The `ARQUIVO` rows equal `arquivo_vendas`,
`com_acesso` = 0 and `arquivo_fora` = 0.

- [X] T005 [P] [US2] Create `src/pipeline/02_silver/10_vw_silver_tb_venda_files.sql`, `CREATE TEMPORARY VIEW vw_silver_tb_venda_files`:
  - **inner query** `FROM STREAM(vw_bronze_dados_files)`, selecting `nome_empresa`, `nome_funcionario`, `data_venda`, `curso`, `disconto` and defining:
    - `preco`: `try_cast(replace(regexp_replace(valor, '[^0-9,]', ''), ',', '.') AS DECIMAL(9,2))`;
    - `fracao`: `CAST(CAST(replace(coalesce(disconto, '0%'), '%', '') AS DECIMAL(5,2)) / 100 AS DECIMAL(5,2))`;
    - `valor_desconto`: `CAST(preco * fracao AS DECIMAL(9,2))`.
  - **outer query**, the 13 columns in the conventions' order:
    - `venda_uuid`: `md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''), coalesce(cast(data_venda AS STRING), ''), coalesce(curso, '')))`;
    - `CAST(data_venda AS TIMESTAMP) AS data_venda`;
    - `CAST(NULL AS STRING) AS acesso_uuid`;
    - `usuario_uuid`: copied character for character from `src/pipeline/02_silver/07_vw_silver_tb_usuario_files.sql`;
    - `md5(curso) AS curso_uuid`;
    - `'pix' AS forma_pagamento`, `1 AS quantidade_parcelas` (typed `INT`);
    - `CAST(preco - valor_desconto AS DECIMAL(9,2)) AS valor_parcelas`;
    - `CAST(quantidade_parcelas * valor_parcelas AS DECIMAL(9,2)) AS valor_pago`;
    - `coalesce(disconto, '0%') AS percentual_desconto`;
    - `valor_desconto`, `'ARQUIVO' AS origem`, `current_timestamp() AS data_carga`.

  The header comment in Portuguese says a corporate sale has no access, is a single `pix` payment, and that `usuario_uuid` is written as in `07_vw_silver_tb_usuario_files.sql`.

---

## Phase 5: User Story 3 - Amounts and discounts that compare across sources (Priority: P2)

**Goal**: one discount form in both sources, no empty or negative amounts, and exact
discount amounts.

**Independent Test**: quickstart.md step 3. `percentual_fora`, `sem_valor_desconto` and
`valor_invalido` are 0, and the discount amounts per course and percentage match
research.md's table.

- [X] T006 [US3] Review `src/pipeline/02_silver/09_vw_silver_tb_venda_api.sql` and `src/pipeline/02_silver/10_vw_silver_tb_venda_files.sql` for the amounts:
  - every amount is `DECIMAL(9,2)` and the fraction `DECIMAL(5,2)`; no amount is computed from a `DOUBLE` without the cast;
  - no discount gives `0%` and `0.00` in both views;
  - `preco` uses `regexp_replace(..., '[^0-9,]', '')` and never `replace(..., ',', '')`, the earlier pipeline's defect.

---

## Phase 6: Review and deploy (shared by all stories)

- [X] T007 Review the three files against contracts/silver-tb-venda.md:
  - both flow views list the 13 column names in the same order;
  - the inner-query definitions of `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso`, `acesso_uuid`, `usuario_uuid` and `curso_uuid` in `09_` match `05_tb_acesso.sql` line for line (`diff` the extracted lines), and the files `usuario_uuid` in `10_` matches `07_vw_silver_tb_usuario_files.sql`;
  - no `UNION`, `uuid()`, `rand()`, ` concat(` inside a key, `AUTO CDC`, `ON VIOLATION`, `MATERIALIZED`, `CLUSTER`, `PARTITIONED`, `LIVE` or `ai_`;
  - no reference to `workspace.bronze`.
- [X] T008 Upload with `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free`. Confirm that `02_silver/` lists eleven `FILE`s, and that the three new copies are identical to the repository
- [X] T009 Following the quota conventions, dry run (`--validate-only`) to `COMPLETED`, with the two flow views and `tb_venda` defined and two flows into `tb_venda`. Report any error to the owner
- [ ] T010 Following the quota conventions, run the update to `COMPLETED` and record its `update_id`. Confirm the existing tables wrote only new data. If it fails after creating `tb_venda` and a fix changes its columns, **stop and ask the owner** to approve a refresh of `workspace.silver.tb_venda` only

---

## Phase 7: Validation

- [ ] T011 [US1] Run quickstart.md step 3 for the `API` rows:
  - `linhas` = `api_vendas` (T002) and `com_acesso` = `linhas`;
  - `sem_chave`, `valor_invalido`, `sem_data_carga` = 0;
  - `api_sem_acesso` = `acesso_descartado` (T002);
  - `curso_fora` = 0.
- [ ] T012 [US2] Run quickstart.md step 3 for the `ARQUIVO` rows:
  - `linhas` = `arquivo_vendas` (T002), `com_acesso` = 0, `arquivo_fora` = 0;
  - across the whole table, `chaves_repetidas` = 0 and `sem_usuario` = `usuario_descartado` (T002);
  - the column list is the 13 of the data model, in order;
  - `quality` = `silver`.
- [ ] T013 [US3] Run the discount query of quickstart.md step 3:
  - `percentual_fora` = 0 and `sem_valor_desconto` = 0;
  - for each course and percentage, `min(valor_desconto)` = `max(valor_desconto)` = the amount in research.md's table, and `0.00` for `0%`.
- [ ] T014 Run quickstart.md step 4 for the update of T010. For dataset `tb_venda`, every expectation has failed = 0 and passed = `api_vendas` + `arquivo_vendas`. Reconcile per source: candidates = rows, with no exclusion. Confirm `tb_quarentena` is unchanged by this feature
- [ ] T015 Ask the owner to confirm that the Data quality tab of `tb_venda` shows the five expectations. Record the answer

---

## Phase 8: Polish

- [ ] T016 Following the quota conventions, run an update with no new data. Confirm that both `tb_venda` flows write 0 rows and the counts of T011–T012 are unchanged
- [ ] T017 [P] In `doc/pipeline-reference.md`:
  - rewrite `### tb_venda` as built: the two append flows and their views, the 13 columns per source, `venda_uuid`'s business columns, the five expectations, the reconciliation with no exclusion, and the unmatched access and user keys with their counts;
  - mark `vw_silver_tb_venda_api` and `vw_silver_tb_venda_files` as built in `### Temporary views`, linked to `09_` and `10_`;
  - add them and `tb_venda` to the intro's "as built" list.
- [ ] T018 [P] In `doc/architecture.md`, point the features-table row "Multiple append flows into one table (`CREATE FLOW ... INSERT INTO ... BY NAME`)" to `../src/pipeline/02_silver/11_tb_venda.sql`
- [ ] T019 [P] In `doc/README.md`, add `09_vw_silver_tb_venda_api.sql`, `10_vw_silver_tb_venda_files.sql` and `11_tb_venda.sql` to the `02_silver/` layout, and change the dataset count to: in silver, 6 streaming views, 1 private streaming table and 4 streaming tables
- [ ] T020 [P] In `doc/known-issues.md`, remove "File sales get a wrong paid amount", and reduce "Sales missing from fato_venda" to its gold part: the silver key mismatch for `unknown` access points and the empty discount no longer occur in `tb_venda`
- [ ] T021 Final review:
  - the workspace copies are identical to the repository;
  - `git status` shows changes only in `src/pipeline/02_silver/`, `doc/` and `specs/007-silver-tb-venda/`;
  - the files of features 004–006 are unchanged.

  Complete the Implementation notes.

---

## Dependencies & Execution Order

- Setup (T001) → Foundational (T002) → definitions (US1 T003–T004, US2 T005, US3 review
  T006) → review and deploy (T007–T010) → validation (T011–T015) → Polish (T016–T021).
- T002 blocks every file, because it decides the two allowed fallbacks.
- US1 and US2 share `11_tb_venda.sql`, which holds both flows. The target needs both flow
  views, so the stories are deployed together and validated separately. US3 has no file
  of its own: its logic lives in the two flow views, and it is validated on the same
  deploy.
- Parallel: T003 and T005 (separate files); T017, T018, T019 and T020 (separate docs).

## Parallel Example

```text
After T002:
  T003 [US1] 09_vw_silver_tb_venda_api.sql
  T005 [US2] 10_vw_silver_tb_venda_files.sql
then T004 (11_tb_venda.sql), T006, T007.

After T016:
  T017 pipeline-reference.md | T018 architecture.md | T019 README.md | T020 known-issues.md
```

## Implementation Strategy

One deploy for all stories, because each Free Edition update costs a quota cycle and the
target with both flows is one file. MVP = US1 validated (T011). US2 and US3 are then
proven on the same deployed definition.

## Implementation notes

### 2026-10-28

**T001**: the `databricks-free` login had expired; the owner renewed it. Pipeline `IDLE`
(last updates `0ea40874-...` and `ac8f733d-...`, both `COMPLETED`); `02_silver/` held
`01_`–`08_`; `workspace.silver` held `tb_acesso`, `tb_quarentena` and `tb_usuario`.

**T002** (quickstart step 1):
- payload type: `info_pagamento` is `struct<disconto: double, forma_pagamento: string,
  quantidade_parcelas: bigint, valor: double, valor_parcelas: double>`. The field is
  `valor_parcelas`, so the Decision 6 fallback is not needed. `information_schema`'s
  `data_type` shows only `STRUCT`; the field list is in `full_data_type` (quickstart
  corrected).
- API: `api_vendas` 220,472; `sem_desconto` 154,314; `acesso_descartado` 2,174;
  `usuario_descartado` 4,362; no event without a user name or a readable date.
- `parcelas_divergentes` 78,578 rows, net difference −535.23: installments ×
  installment value differs from the paid amount by cents in 35.6% of API sales.
  Reported to the owner; no change (research Decision 7).
- `chaves_venda_repetidas` (API, four components) **1,311**, in 624 groups of up to 9
  rows, **all with the address `999.999.999.999`**, the events `tb_acesso` drops. That is
  why `acesso_uuid` is unique in `tb_acesso` (0 repeats in 2,516,192 rows). With
  `payload.info_usuario.nome` as a fifth component: 0 repeats. **The Decision 4 fallback
  is applied** (research and data model updated). These 2,174 sales also share
  `acesso_uuid` values among themselves; none of them joins `tb_acesso`.
- Files: `arquivo_vendas` 200,000; 0 repeated keys; prices `R$ 247,00`, `R$ 997,00`,
  `R$ 2497,00`; discounts `5%`, `10%`, `15%`; no empty price or discount.
- Expected `tb_venda`: 220,472 + 200,000 = **420,472** rows.

**T003–T007**: three files written. The 16 key lines of `09_` (from `timestamp_acesso` to
`curso_uuid`) equal `05_tb_acesso.sql`'s once indentation is ignored; the files
`usuario_uuid` equals `07_`'s. Both views list the 13 columns in the same order. The only
forbidden-token hits are the `concat` that builds `percentual_desconto` (not a key) and
the word `UNION` in a comment. No `replace(..., ',', '')`.

**T008**: upload complete; `02_silver/` lists eleven `FILE`s, and the three new copies are
identical to the repository.

**T009**: warehouse stopped, pipeline `IDLE`. Dry run `93b3c979-3722-4afa-aeaa-8ad51ac0e8ae`
**COMPLETED**, no error event. `vw_silver_tb_venda_api`, `vw_silver_tb_venda_files` and the
two flows are defined. The flows appear as `workspace.bronze.silver_tb_venda_api_flow` and
`workspace.bronze.silver_tb_venda_files_flow`, like `tb_usuario`'s (open finding).
