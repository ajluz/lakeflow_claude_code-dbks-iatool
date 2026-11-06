---

description: "Task list for feature 014: gold access one-big-table"
---

# Tasks: Gold Access One-Big-Table

**Input**: Design documents from `/specs/014-gold-obt-acesso/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/gold-obt-acesso.md](contracts/gold-obt-acesso.md),
[quickstart.md](quickstart.md)

**Tests**: no test tasks. The spec requests none, and the project has no test framework.
Each story is verified by the [quickstart.md](quickstart.md) queries named in its tasks.

**Organization**: one file, `src/pipeline/03_gold/08_obt_acesso.sql`, holding one materialized
view. Each story writes its part of the query:
- US1: the accesses grouped by location, address and day, with `qtde_acesso` and the
  calendar columns;
- US2: `qtde_usuario`;
- US3: the sales link and `qtde_vendidos`.

The view's 19 columns need all three parts, so the code tasks run in sequence on the same
file and the pipeline runs once. Each story then has its own validation task.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Conventions for every task

- Profile `databricks-free`, passed explicitly; pipeline
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`; warehouse `f796ffb64302b6ba`.
- Workspace folder of the pipeline source:
  `WS=/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline`.
- **Upload**: `databricks workspace import-dir src/pipeline $WS --overwrite --profile databricks-free`.
  Then confirm that
  `databricks workspace export $WS/03_gold/08_obt_acesso.sql --format AUTO --profile databricks-free | cmp - src/pipeline/03_gold/08_obt_acesso.sql`
  reports no difference.
- **Dry run**: `databricks pipelines start-update <id> --validate-only --profile databricks-free`.
  - An update is the same command without `--validate-only`. **Never** pass
    `--full-refresh`; `start-update` has no `--full-refresh-selection` flag.
  - Poll `databricks pipelines get-update <id> <update_id>` until the state is `COMPLETED`
    or `FAILED`, and check that the update id is not empty before polling.
  - On failure, read `error.exceptions[0].message` in
    `databricks pipelines list-pipeline-events`.
- Never drop a table. Leave about 4 minutes between updates.
- Run SQL with `databricks experimental aitools tools query <file.sql> --profile databricks-free -o json`.
- Stop the warehouse after each validation session with `--no-wait`.
- Code comments are in Portuguese; documentation is in English. zsh: never echo `=====`.

---

## Phase 1: Setup

**Purpose**: confirm the environment the plan assumes.

- [X] T001 Confirm the preconditions and record them in the Implementation Notes at the end of `specs/014-gold-obt-acesso/tasks.md`:
  - pipeline `IDLE`; `workspace.gold.obt_acesso` does not exist (`workspace.information_schema.tables`);
  - workspace `03_gold/` holds `01_`–`07_` and nothing else;
  - baseline: `tb_acesso` 2,516,192, `tb_venda` 420,472, `dim_tempo` 3,654, `fato_venda` 420,472 (checksum `sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))` 581165462078), `dim_usuario` 956,251, `dim_codigos` 62, `dim_curso` 5.
  If any count differs, re-measure research.md Decision 6 before continuing and use the new values as the expected ones.

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: the grain is documented before the build (FR-013; constitution, Principle VII).

- [X] T002 Rewrite the `### obt_acesso` section of `doc/pipeline-reference.md`:
  - link `[08_obt_acesso.sql](../src/pipeline/03_gold/08_obt_acesso.sql)`, "materialized view `workspace.gold.obt_acesso`, recomputed on every update. As built (feature 014)";
  - **Grain**: one row per combination of `local_acesso`, `endereco_ip_acesso` and `data` (the access day); the counts are summed over that combination's accesses;
  - a column table: `local_acesso`, `endereco_ip_acesso` (from `tb_acesso`); `data` (the access day); the 13 calendar columns from `dim_tempo` with its names; `qtde_acesso` (accesses), `qtde_usuario` (accesses with a user), `qtde_vendidos` (site sales linked to the accesses, counted per access first, so no access is duplicated);
  - **Sources**: `silver.tb_acesso`, `silver.tb_venda`, `gold.dim_tempo`; `fato_venda` is not used because it stores no access identifier;
  - **Reconciliation**: `sum(qtde_acesso)` = rows of `tb_acesso`; both joins are left joins from the accesses, so no access is lost.
  Remove the old description (one row per access, "always 1", the `code_tips` link).

**Checkpoint**: the grain is written down; the code can be built.

---

## Phase 3: User Story 1 - Site accesses by device and calendar, without joins (Priority: P1) 🎯 MVP

**Goal**: every access counted once in its (location, address, day) row, with the day's calendar attributes.

**Independent Test**: quickstart.md steps 2 (`dif_acesso` 0, `linhas` 2,516,058), 3 and 4 (`qtde_acesso` per location and per day).

- [X] T003 [US1] Create `src/pipeline/03_gold/08_obt_acesso.sql`:
  - **header comment (Portuguese)**: grain (uma linha por local_acesso, endereco_ip_acesso e data do acesso; contagens somadas por combinação); sources (`silver.tb_acesso`, `silver.tb_venda`, `gold.dim_tempo`; `fato_venda` não guarda o acesso); joins à esquerda a partir dos acessos, nenhum acesso se perde; the measures stay defined in their own datasets (this table only counts them);
  - `CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.obt_acesso`, `COMMENT` in Portuguese (one-big-table de acessos do site por local, endereço e dia, com o calendário e as quantidades de acessos, usuários e vendas), `TBLPROPERTIES ("quality" = "gold")`, `AS`;
  - CTE `acessos` over `workspace.silver.tb_acesso AS a`, without `STREAM`: `a.local_acesso`, `a.endereco_ip_acesso`, `CAST(a.timestamp_acesso AS DATE) AS data`, `count(*) AS qtde_acesso`, `GROUP BY a.local_acesso, a.endereco_ip_acesso, CAST(a.timestamp_acesso AS DATE)`;
  - final `SELECT` from `acessos AS s LEFT JOIN workspace.gold.dim_tempo AS t ON t.data = s.data`: `s.local_acesso`, `s.endereco_ip_acesso`, `s.data`, then `t.ano`, `t.mes`, `t.mes_ano`, `t.dia_mes`, `t.dia_semana`, `t.dia_semana_int`, `t.fl_dia_semana`, `t.dia_ano`, `t.fl_ultimo_dia_mes`, `t.semana_ano`, `t.semestre`, `t.trimestre`, `t.bimestre`, then `s.qtde_acesso`;
  - no `current_timestamp()`, no `STREAM`, no `PARTITIONED BY`, no expectations.

---

## Phase 4: User Story 2 - Identified users among the accesses (Priority: P1)

**Goal**: `qtde_usuario` counts the accesses that carry a user.

**Independent Test**: quickstart.md step 2 (`dif_usuario` 0) and step 4 (`qtde_usuario` per location and per day).

- [X] T004 [US2] In `src/pipeline/03_gold/08_obt_acesso.sql`, add `count_if(a.usuario_uuid IS NOT NULL) AS qtde_usuario` to the CTE `acessos`, and `s.qtde_usuario` to the final `SELECT` right after `s.qtde_acesso`. Add one header line: qtde_usuario conta os acessos com usuário identificado

---

## Phase 5: User Story 3 - Accesses that ended in a sale (Priority: P1)

**Goal**: `qtde_vendidos` counts the site sales linked to the accesses, without duplicating any access.

**Independent Test**: quickstart.md step 2 (`dif_vendidos` 0) and step 4 (`qtde_vendidos` per location and per day).

- [X] T005 [US3] In `src/pipeline/03_gold/08_obt_acesso.sql`:
  - add a first CTE `vendas_por_acesso`: `SELECT acesso_uuid, count(*) AS qtde_vendas FROM workspace.silver.tb_venda WHERE origem = 'API' AND acesso_uuid IS NOT NULL GROUP BY acesso_uuid`, with a Portuguese comment: as vendas são contadas por acesso antes do join, para que um acesso com mais de uma venda não se repita;
  - in `acessos`, `LEFT JOIN vendas_por_acesso AS v ON v.acesso_uuid = a.acesso_uuid`, and add `coalesce(sum(v.qtde_vendas), 0) AS qtde_vendidos`;
  - in the final `SELECT`, add `s.qtde_vendidos` as the last column;
  - header line: qtde_vendidos conta as vendas do site ligadas aos acessos; vendas de arquivo e vendas sem acesso em tb_acesso não entram.

---

## Phase 6: Deploy (shared by all stories)

- [X] T006 Review `src/pipeline/03_gold/08_obt_acesso.sql` against [contracts/gold-obt-acesso.md](contracts/gold-obt-acesso.md) and [data-model.md](data-model.md): exactly 19 columns, in FR-003 order (`local_acesso`, `endereco_ip_acesso`, `data`, `ano`, `mes`, `mes_ano`, `dia_mes`, `dia_semana`, `dia_semana_int`, `fl_dia_semana`, `dia_ano`, `fl_ultimo_dia_mes`, `semana_ano`, `semestre`, `trimestre`, `bimestre`, `qtde_acesso`, `qtde_usuario`, `qtde_vendidos`); both joins are `LEFT JOIN`s from the accesses; reads only `silver.tb_acesso`, `silver.tb_venda`, `gold.dim_tempo`. Before uploading, run the view's query (without `CREATE`) as a batch and confirm 2,516,058 rows and sums 2,516,192 / 748,571 / 218,298
- [ ] T007 Upload (conventions), confirm `03_gold/` lists `01_`–`08_` and the `cmp` shows no difference. Dry run to `COMPLETED` with `obt_acesso` defined; at least 4 minutes later, an ordinary update to `COMPLETED`. Record both update ids. If the update fails, record the error and stop; never use a full refresh

**Checkpoint**: `workspace.gold.obt_acesso` exists as a `MATERIALIZED_VIEW`.

---

## Validation per story

- [ ] T008 [US1] Run quickstart.md for the update of T007: step 2 `dif_acesso` 0 and `linhas` 2,516,058; step 3 `combinacoes_repetidas` 0, `sem_acesso` 0, `sem_data` 0, `maior_qtde` 2, calendar `divergentes` 0, the 19 columns in order with the data-model types, `quality` = `gold`; step 4 `qtde_acesso` per location (`Computador` 1,136,377, `Mobile` 1,262,684, `unknown` 117,131) and per day (881,045; 880,259; 754,888)
- [ ] T009 [P] [US2] Run quickstart.md step 2 `dif_usuario` 0 and step 4 `qtde_usuario` per location (340,520; 379,439; 28,612) and per day (262,742; 260,646; 225,183)
- [ ] T010 [P] [US3] Run quickstart.md step 2 `dif_vendidos` 0 and step 4 `qtde_vendidos` per location (102,148; 113,846; 2,304) and per day (77,232; 75,597; 65,469)

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T011 At least 4 minutes after T007, run a second ordinary update. Confirm `obt_acesso`'s row count and three sums are unchanged, and that the other datasets keep the T001 counts (`fato_venda` checksum 581165462078 included) (quickstart step 5). Stop the warehouse with `--no-wait`
- [ ] T012 [P] In `doc/architecture.md` line 134 (Materialized views row), replace the `code_tips` link with `[08_obt_acesso.sql](../src/pipeline/03_gold/08_obt_acesso.sql)`
- [ ] T013 [P] In `doc/README.md`: add `│           └── 08_obt_acesso.sql         Access one-big-table: materialized view by location, address and day` to the `03_gold/` layout (line 53's `└──` becomes `├──`); in line 82, gold becomes "3 streaming views, 3 streaming tables and 2 materialized views"
- [ ] T014 [P] In `doc/known-issues.md`, remove the sentence saying `obt_acesso` is still the earlier pipeline's `05_obt_acesso.sql` (lines 18–20), keeping the `fato_venda` sentence as its own bullet
- [ ] T015 Final review: `08_obt_acesso.sql` identical in the workspace; no `code_tips/03_gold/05_obt_acesso.sql` link left in `doc/`; `### obt_acesso` matches the built view; record the update ids and results of T007–T011 in the Implementation Notes

---

## Dependencies & Execution Order

- T001 → T002 → T003 → T004 → T005 (same file, in sequence) → T006 → T007.
- After T007: T008 first, then T009 and T010 in parallel.
- T011 after the validations. T012, T013 and T014 in parallel any time after T007. T015 last.

### Parallel opportunities

- T009 and T010: independent queries.
- T012, T013, T014: different documentation files.

---

## Implementation Strategy

**MVP**: T001–T008 deliver US1, the access counts by device and calendar. Because the three
counts live in one view, US2 and US3 are written before the single deploy and validated
right after it. No full refresh and no table drop at any point.

---

## Implementation Notes
