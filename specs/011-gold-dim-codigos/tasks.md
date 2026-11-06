---

description: "Task list for feature 011: gold junk dimension of sale codes"
---

# Tasks: Gold Junk Dimension of Sale Codes

**Input**: Design documents from `/specs/011-gold-dim-codigos/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/gold-dim-codigos.md](contracts/gold-dim-codigos.md),
[quickstart.md](quickstart.md)

**Tests**: no test tasks; the spec requests none and the project has no test framework.
Each story is verified by the [quickstart.md](quickstart.md) queries named in its tasks.

**Organization**: one file, `src/pipeline/03_gold/03_dim_codigos.sql`, grown story by
story. Three pipeline updates in total: US1 creates the view, US2 runs an unchanged
update to prove key stability, US3 adds the members. None is a full refresh.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Conventions for every task

- Profile `databricks-free`, passed explicitly; pipeline
  `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`; warehouse `f796ffb64302b6ba`.
- Workspace folder of the pipeline source:
  `WS=/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline`.
- Upload: `databricks workspace import-dir src/pipeline $WS --overwrite --profile databricks-free`,
  then confirm `03_gold/03_dim_codigos.sql` in the workspace is identical to the repository
  (`databricks workspace export $WS/03_gold/03_dim_codigos.sql --format AUTO --profile databricks-free | cmp - src/pipeline/03_gold/03_dim_codigos.sql`).
- Dry run: `databricks pipelines start-update <id> --validate-only --profile databricks-free`;
  update: the same without `--validate-only`. Poll `databricks pipelines get-update <id> <update_id>`
  until `COMPLETED` or `FAILED`; on failure read `error.exceptions[0].message` in
  `databricks pipelines list-pipeline-events`.
- Never `--full-refresh`. About 4 minutes between updates (Free Edition quota).
- Run SQL with `databricks experimental aitools tools query "<sql>" --profile databricks-free`.
- Stop the warehouse after each validation session with `--no-wait`.
- Code comments in Portuguese; documentation in English.

---

## Phase 1: Setup

**Purpose**: confirm the environment the plan assumes.

- [X] T001 Confirm preconditions: the pipeline is `IDLE` (`databricks pipelines get 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free`); `databricks tables get workspace.gold.dim_codigos --profile databricks-free` reports it does not exist; `databricks workspace list $WS/03_gold --profile databricks-free` shows only `01_vw_gold_dim_usuario_tb_usuario.sql` and `02_dim_usuario.sql`. Record `SELECT count(*) FROM workspace.gold.dim_usuario` (expect 941,236), `SELECT count(*) FROM workspace.silver.tb_venda` (420,472) and `SELECT count(*) FROM workspace.silver.tb_acesso` for the "nothing else changed" check

---

## Phase 2: Foundational

**Purpose**: the file and the view declaration every story builds on.

- [X] T002 Create `src/pipeline/03_gold/03_dim_codigos.sql` with:
  - a header comment in Portuguese, in the style of `src/pipeline/03_gold/02_dim_usuario.sql`: "Camada gold: dimensão junk de códigos da venda (dim_codigos)"; grain: every possible combination of `origem_usuario`, `local_acesso`, `forma_pagamento`, `percentual_desconto`; SCD type 1; built from four value lists (origin, payment method and discount from `silver.tb_venda`; access location from `silver.tb_acesso` plus `Desconhecido`), crossed with each other, never the tables (crossing the tables multiplies sales by accesses); the code rules (`ARQUIVO` → `local_acesso` = `Não se aplica`; empty payment method → `Desconhecido`; empty discount → `Não se aplica`); the key is `xxhash64` of the four codes with the sign bit cleared, deterministic and therefore never reassigned, not an identity (not supported on materialized views); members `-1` / `-2`; a fact resolves `sk_codigos` by computing the same four codes and matching them, falling back to `-1`;
  - `CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_codigos` with a Portuguese `COMMENT` ("Dimensão junk: uma linha por combinação possível de origem, local de acesso, forma de pagamento e percentual de desconto, com chave substituta estável e os membros -1 e -2.") and `TBLPROPERTIES ("quality" = "gold")`; no column list, no `CLUSTER BY`, no `PARTITIONED BY`, no constraints (FR-010)

**Checkpoint**: the declaration exists; its query is written in US1.

---

## Phase 3: User Story 1 - One row per combination of sale codes (Priority: P1) 🎯 MVP

**Goal**: the cross product of the code values, one row each, with a key.

**Independent Test**: 60 combinations (`API` 48, `ARQUIVO` 12), equal to the product of the
list sizes; every one of the 420,472 sales finds exactly one row (quickstart steps 2–3).

- [X] T003 [US1] Write the view's query in `src/pipeline/03_gold/03_dim_codigos.sql` (research, Decisions 2–4 and 6):
  - CTE `origens`: `SELECT DISTINCT origem AS origem_usuario FROM workspace.silver.tb_venda`;
  - CTE `locais`: `SELECT DISTINCT local_acesso FROM workspace.silver.tb_acesso UNION SELECT 'Desconhecido'`;
  - CTE `formas`: `SELECT DISTINCT coalesce(forma_pagamento, 'Desconhecido') AS forma_pagamento FROM workspace.silver.tb_venda`;
  - CTE `descontos`: `SELECT DISTINCT coalesce(percentual_desconto, 'Não se aplica') AS percentual_desconto FROM workspace.silver.tb_venda`;
  - CTE `combinacoes`: `SELECT DISTINCT o.origem_usuario, CASE WHEN o.origem_usuario = 'ARQUIVO' THEN 'Não se aplica' ELSE l.local_acesso END AS local_acesso, f.forma_pagamento, d.percentual_desconto FROM origens AS o CROSS JOIN locais AS l CROSS JOIN formas AS f CROSS JOIN descontos AS d`;
  - final `SELECT xxhash64(origem_usuario, local_acesso, forma_pagamento, percentual_desconto) & 9223372036854775807 AS sk_codigos, origem_usuario, local_acesso, forma_pagamento, percentual_desconto, current_timestamp() AS data_carga FROM combinacoes`, columns in exactly this order (FR-002);
  - short Portuguese comments: above `locais` ("Desconhecido: venda do site sem acesso em tb_acesso"), above `combinacoes` ("cruza as listas de valores, não as tabelas"), above the key ("determinística: a mesma combinação tem sempre a mesma chave")
- [X] T004 [US1] Upload `src/pipeline` and confirm the workspace copy of `03_gold/03_dim_codigos.sql` is identical (Conventions). Run a dry run; expect `COMPLETED` and `dim_codigos` in the graph as a materialized view. Fix and repeat on failure
- [X] T005 [US1] Start an update (not a full refresh); expect `COMPLETED`, `dim_codigos` created as `MATERIALIZED_VIEW` (`databricks tables get workspace.gold.dim_codigos`), no failed flow. Then run [quickstart.md](quickstart.md) step 2 (expect `linhas` 60, `chaves` 60, `combinacoes` 60, `vazios` 0, `membros` 0 until US3, `chave_zero` 0, `arquivo_errado` 0, `api_errado` 0, `api` 48, `arquivo` 12, `sem_acesso` 12), the list-product query (`esperado_api` 48, `esperado_arquivo` 12) and step 3 (`vendas` 420472, `sem_linha` 0, `combinacoes_usadas` 22). Check `DESCRIBE TABLE workspace.gold.dim_codigos` lists the six columns in FR-002 order with `sk_codigos` BIGINT, and `SHOW TBLPROPERTIES workspace.gold.dim_codigos ('quality')` returns `gold`. Record the update id

**Checkpoint**: MVP: every sale has a code row.

---

## Phase 4: User Story 2 - Surrogate keys that never change (Priority: P1)

**Goal**: an update rebuilds the view and every key comes back the same.

**Independent Test**: `linhas` and `checksum` of quickstart step 4 identical across two
updates; the second update's planning event shows a complete recompute.

- [X] T006 [US2] Record quickstart step 4 (`linhas`, `checksum`, and `max(data_carga)`) for `workspace.gold.dim_codigos`. At least 4 minutes after T005's update, start another update with no code change; expect `COMPLETED`. Repeat step 4: `linhas` 60 and `checksum` identical, `max(data_carga)` later (SC-004). In `databricks pipelines list-pipeline-events 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free`, find the `planning_information` event of `dim_codigos` for this update and record its technique (expected a complete recompute, research Decision 6); if it says incremental, record that too: keys are deterministic either way

**Checkpoint**: keys proven stable across a rebuild.

---

## Phase 5: User Story 3 - Explicit members for unknown and not-applicable codes (Priority: P2)

**Goal**: rows `-1` and `-2`, each once, with labels in all four codes.

**Independent Test**: quickstart step 2 `membros` 2 and the members query; positive keys
unchanged from US2.

- [X] T007 [US3] In `src/pipeline/03_gold/03_dim_codigos.sql`, add the members to the final query with `UNION ALL` (research, Decision 5): `SELECT CAST(-1 AS BIGINT) AS sk_codigos, 'Desconhecido', 'Desconhecido', 'Desconhecido', 'Desconhecido', current_timestamp()` and `SELECT CAST(-2 AS BIGINT), 'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica', current_timestamp()`, column order matching the combinations ("`-1` with `Desconhecido` and `-2` with `Não se aplica` in all four code columns", FR-006). Portuguese comment above: members for facts whose codes are missing or do not apply; a member never equals a combination because a combination's `origem_usuario` is `API` or `ARQUIVO`
- [X] T008 [US3] Upload, confirm the workspace copy is identical, dry run, then (at least 4 minutes after T006) an update; expect `COMPLETED`. Quickstart step 2: `linhas` 62, `chaves` 62, `combinacoes` 62, `membros` 2, `vazios` 0, other counts as in T005; the members query returns `-1` with `Desconhecido` ×4 and `-2` with `Não se aplica` ×4. Step 4 restricted to `WHERE sk_codigos > 0` gives the same `linhas` (60) and `checksum` as T006

**Checkpoint**: all three stories done; the view is complete.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: documentation (FR-011) and final validation.

- [X] T009 [P] Rewrite `### dim_codigos` in `doc/pipeline-reference.md`: [03_dim_codigos.sql](../src/pipeline/03_gold/03_dim_codigos.sql), materialized view, as built; grain every possible combination; the four value lists and their sources, crossed with each other, not the tables; the code rules; key `xxhash64(<4 codes>) & 9223372036854775807`, never reassigned; members; SCD type 1; 62 rows on 2026-11-05 (22 combinations used by sales); `data_carga` = time of the latest update. In `### fato_venda`, change the `sk_codigos` row to "the four codes computed by `dim_codigos`'s rules, matched on all four; no match → `-1`"
- [X] T010 [P] In `doc/known-issues.md`, delete the `## dim_codigos is built from a cross join` section; in "Smaller items", change the identity bullet so it no longer names `dim_codigos` (only `dim_curso` remains in the earlier pipeline) and add that `dim_codigos` now uses a deterministic key since feature 011
- [X] T011 [P] In `doc/architecture.md` features table: remove `03_dim_codigos.sql` from the "Explicit schema with identity surrogate keys" row; add [03_dim_codigos.sql](../src/pipeline/03_gold/03_dim_codigos.sql) to the "Deterministic surrogate key" row and to the "Materialized views" row; add a row "Junk dimension: cross join of value lists" pointing to the same file
- [X] T012 [P] In `doc/README.md`: add `│           └── 03_dim_codigos.sql        Junk dimension: materialized view, cross join of code values, deterministic key` under `03_gold/` (moving the `└──` from `02_dim_usuario.sql` to `├──`); in "Pipeline datasets", gold becomes "1 streaming view, 1 streaming table and 1 materialized view"
- [X] T013 Final validation: confirm the workspace copy of `src/pipeline` matches the repository for all three `03_gold` files; rerun quickstart steps 2 and 3 on the current state (62 rows, 0 sales without a row); step 5: `dim_usuario` 941,236 rows and silver counts equal to T001; the pipeline is `IDLE`; stop the warehouse with `--no-wait`
- [X] T014 Constitution review of `src/pipeline/03_gold/03_dim_codigos.sql`: `CREATE OR REFRESH MATERIALIZED VIEW`; no `STREAM`, no legacy syntax, no `CREATE OR REPLACE`, no constraints, no `CLUSTER BY` / `PARTITIONED BY`; three-level names; no `CROSS JOIN` between `tb_venda` and `tb_acesso` rows (only between the four lists); Portuguese comments. Record the outcome in an "Implementation Notes" section at the end of this file

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2 → US1 → US2 → US3 → Phase 6.**
- T003 needs T002 (same file). T004 needs T003. T005 needs T004.
- T006 needs T005 and the 4-minute gap.
- T007 can be written any time after T003 (same file, so after it), but is uploaded only in
  T008, after T006, so that US2's update runs on the US1 code.
- T009–T012 touch different files and can run in parallel after T008 (the docs state the
  final 62 rows). T013 after T009–T012; T014 last.

### Parallel opportunities

```text
After T008:   T009 (pipeline-reference), T010 (known-issues), T011 (architecture), T012 (README)
```

All code tasks edit one file and stay sequential.

## Implementation Strategy

1. **MVP**: T001–T005. The 60 combinations exist and every sale finds its row.
2. **Stable keys**: T006. A second update rebuilds the view; keys identical.
3. **Members**: T007–T008. Rows `-1` / `-2` added by a third update; real keys unchanged.
4. **Polish**: docs, final checks, constitution review.

Pipeline time: three updates, each at least 4 minutes apart, about 15 minutes of waiting in
total.

---

## Implementation Notes (2026-11-05)

- **T001**: pipeline `IDLE`; `dim_codigos` absent; workspace `03_gold` held only the two
  `dim_usuario` files. Baseline: `dim_usuario` 941,236; `tb_venda` 420,472; `tb_acesso`
  2,516,192; `tb_usuario` 941,234; bronze api 2,550,955, files 200,000, database 3.
- **T004**: upload identical for all three `03_gold` files; dry run `1d2a7e02` COMPLETED.
- **T005**: update `040a7c6f` COMPLETED. `MATERIALIZED_VIEW`, six columns in FR-002 order
  (`sk_codigos` reported as `LONG` = BIGINT), `quality` = `gold`. 60 rows: `API` 48,
  `ARQUIVO` 12, `Desconhecido` 12; equal to the list product (48 / 12); 0 empty codes, 0
  zero keys, 0 `ARQUIVO`/`API` location errors. All 420,472 sales match a row; they use 22
  combinations. Checksum `-3718906536`.
- **T006**: update `b2153c73` with no code change COMPLETED; planning event "planned to be
  executed as COMPLETE_RECOMPUTE"; 60 rows, checksum `-3718906536` identical, `data_carga`
  moved from 22:01:53Z to 22:03:08Z (SC-004).
- **T008**: dry run `64eb860a` and update `c8df42d9` COMPLETED. 62 rows, 62 keys, 62
  combinations, members `-1` (`Desconhecido` ×4) and `-2` (`Não se aplica` ×4); the 60 real
  rows keep checksum `-3718906536`.
- **T009–T012**: docs updated (pipeline-reference `### dim_codigos` and `fato_venda`'s
  `sk_codigos` row; known-issues cross-join section removed and identity bullet updated;
  architecture features table; README layout and dataset count).
- **T013**: 420,472 sales, 0 without a row; bronze, silver, `dim_usuario` and `dim_tempo`
  counts equal to the baseline; pipeline `IDLE`; warehouse stopped.
- **T014** (constitution review): PASS. `CREATE OR REFRESH MATERIALIZED VIEW`, no `STREAM`,
  no legacy syntax, no constraints, no clustering or partitioning; three-level names;
  `CROSS JOIN` only between the four value lists, never between `tb_venda` and
  `tb_acesso` rows; Portuguese comments.
