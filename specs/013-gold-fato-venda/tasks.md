---

description: "Task list for feature 013: gold sales fact"
---

# Tasks: Gold Sales Fact

**Input**: Design documents from `/specs/013-gold-fato-venda/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/gold-fato-venda.md](contracts/gold-fato-venda.md),
[quickstart.md](quickstart.md)

**Tests**: no test tasks. The spec requests none, and the project has no test framework.
Each story is verified by the [quickstart.md](quickstart.md) queries named in its tasks.

**Organization** (regenerated 2026-11-05 for constitution v3.0.0, where facts are streaming
tables): one file, `src/pipeline/03_gold/07_fato_venda.sql`, holding one streaming table over
`STREAM(workspace.silver.tb_venda)` with stream-static lookups. Each story writes its part
of the query:
- US1: the sales and measures;
- US2: the date, course and user lookups;
- US3: the sale codes with the `ARQUIVO` rule.

The table's six columns need all three parts, so the code tasks run in sequence and the
pipeline runs once. Each story then has its own validation task. A second update proves
stability. Neither update is a full refresh.

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
  `databricks workspace export $WS/03_gold/07_fato_venda.sql --format AUTO --profile databricks-free | cmp - src/pipeline/03_gold/07_fato_venda.sql`
  reports no difference.
- **Dry run**: `databricks pipelines start-update <id> --validate-only --profile databricks-free`.
  - An update is the same command without `--validate-only`.
  - Poll `databricks pipelines get-update` until the state is `COMPLETED` or `FAILED`.
  - On failure, read `error.exceptions[0].message` in
    `databricks pipelines list-pipeline-events`.
- Never `--full-refresh`, and never drop a table. Leave about 4 minutes between updates.
- Run SQL with `databricks experimental aitools tools query "<sql>" --profile databricks-free`.
- Stop the warehouse after each validation session with `--no-wait`.
- Code comments are in Portuguese; documentation is in English. zsh: never echo `=====`.

---

## Phase 1: Setup

**Purpose**: confirm the environment the plan assumes.

- [ ] T001 Confirm the preconditions:
  - the pipeline is `IDLE`;
  - `databricks tables get workspace.gold.fato_venda --profile databricks-free` reports
    that the table does not exist;
  - `databricks workspace list $WS/03_gold` shows `01_` through `06_` only.

  Record the baseline counts:

  | Dataset | Expected rows |
  |---|---|
  | `silver.tb_venda` | 420,472 |
  | `silver.tb_acesso` | 2,516,192 |
  | `gold.dim_tempo` | 3,654 |
  | `gold.dim_usuario` | 941,236 |
  | `gold.dim_codigos` | 62 |
  | `gold.dim_curso` | 5 |

  Also record `sum(valor_pago)` and `sum(valor_desconto)` of `silver.tb_venda`. Confirm that
  `SELECT count(*) - count(DISTINCT acesso_uuid) FROM workspace.silver.tb_acesso` is 0, so
  the access lookup cannot multiply sales (research, Decision 2).
  Confirm that `tb_venda` is append-only (constitution v3.0.0, Principle V):
  `SELECT DISTINCT operation FROM (DESCRIBE HISTORY workspace.silver.tb_venda)` shows no
  `DELETE`, `UPDATE` or `MERGE`. If one appears, stop and report, because the stream would
  need `SKIPCHANGECOMMITS`.

---

## Phase 2: Foundational

**Purpose**: the documented grain (required before the build) and the file's declaration.

- [ ] T002 Rewrite `### fato_venda` in `doc/pipeline-reference.md` **before** any upload
  (Principle VII: the grain is stated before the fact is built; FR-013).
  - **Header**: link to
    [07_fato_venda.sql](../src/pipeline/03_gold/07_fato_venda.sql), "streaming table
    `workspace.gold.fato_venda` over `STREAM(silver.tb_venda)`; dimensions read static
    (stream-static joins)".
  - **Grain**: one row per sale of `silver.tb_venda`.
  - **Column table**, with each key's resolution and `-1` fallback, from
    [data-model.md](data-model.md):
    - `sk_tempo`: `dim_tempo.data` = the sale's day;
    - `sk_codigos`: the four codes, including `ARQUIVO` → `Não se aplica`, and
      `Desconhecido` for a site sale without access;
    - `sk_curso`: the version in effect at `data_venda`, or the course's first version when
      the sale is older; never limited to `__END_AT IS NULL`;
    - `sk_usuario`: `usuario_uuid`.
  - **Measures**: `valor_desconto` and `valor_pago`, both "additive, from silver".
  - **Reconciliation**: the row count equals `tb_venda`'s; there is no exclusion, and every
    lookup is a `LEFT JOIN` with the stream on the left.
  - **Keys resolved once** (Principle V; research, Decision 9): a sale's keys are set when
    it is processed, after the same update's dimensions. A dimension row that arrives in a
    later update does not change sales already written; they keep `-1` until a full
    refresh approved by the owner.
  - **Query joins**: every key exists, so inner joins from the fact to the dimensions
    return every row.
  - **Status**: write "Planned (feature 013)" for now; T012 changes it to "As built".
  - **Remove** the old text "Sales are first joined to `silver.tb_acesso` … All joins are
    inner joins."
- [ ] T003 Create `src/pipeline/03_gold/07_fato_venda.sql` with:
  - **Header comment in Portuguese**, in the style of
    `src/pipeline/03_gold/03_dim_codigos.sql`:
    - "Camada gold: fato de vendas (fato_venda)";
    - grain: one sale of `silver.tb_venda`;
    - measures `valor_desconto` and `valor_pago`, additive;
    - a streaming table over `STREAM(silver.tb_venda)`, append-only, with each sale
      processed once; dimensions are read static (stream-static joins);
    - each key's lookup, with `-1` when nothing matches, and why there is no inner join
      (no sale may be lost: Principles I, V and VII);
    - keys are resolved once, after the same update's dimensions; a dimension row that
      arrives later does not change sales already written;
    - the `ARQUIVO` → `Não se aplica` rule;
    - the course rule: version in effect, else the first version, never only
      `__END_AT IS NULL`.
  - **Declaration**: `CREATE OR REFRESH STREAMING TABLE workspace.gold.fato_venda`, with
    the Portuguese `COMMENT` 'Fato de vendas: uma linha por venda de silver.tb_venda, com
    as chaves de tempo, códigos, curso e usuário e as medidas valor_desconto e
    valor_pago.' and `TBLPROPERTIES ("quality" = "gold")`, followed by `AS` and the query
    of T004–T007.
    - No column list, no constraints (FR-011), no `CLUSTER BY` and no `PARTITIONED BY`.

**Checkpoint**: the grain is documented and the declaration exists. The query is written in
US1–US3.

---

## Phase 3: User Story 1 - Every sale in the fact, with its measures (Priority: P1) 🎯 MVP

**Goal**: one row per sale with silver's measures.

**Independent Test**: quickstart step 2. `linhas_fato` = `linhas_silver` = 420,472;
`dif_pago` and `dif_desconto` are 0.00.

- [ ] T004 [US1] In `src/pipeline/03_gold/07_fato_venda.sql`, write CTE `vendas`
  (research, Decision 3), with one row per sale:
  - **Source**:
    `FROM STREAM(workspace.silver.tb_venda) AS v LEFT JOIN workspace.silver.tb_acesso AS a ON v.origem = 'API' AND a.acesso_uuid = v.acesso_uuid`.
    - `tb_venda` is read as a stream. `tb_acesso` is read without `STREAM`: it is the static
      side, and the stream is on the left.
  - **Columns**:
    - `v.data_venda`, `v.usuario_uuid`, `v.curso_uuid`;
    - `v.valor_desconto`, `v.valor_pago`;
    - `v.origem AS origem_usuario`;
    - `local_acesso`, `forma_pagamento`, `percentual_desconto` (the code expressions are
      written in T007).
  - **Comment above it**, in Portuguese: "Uma linha por venda, lida do stream de
    tb_venda. LEFT JOIN: vendas sem acesso e vendas de arquivo continuam no fato."
  - If the dry run (T008) rejects a CTE over a stream, inline `vendas` as a subquery in the
    final `FROM` instead (plan, Design Notes).
- [ ] T005 [US1] Write the final `SELECT` in `src/pipeline/03_gold/07_fato_venda.sql`:
  - `FROM vendas AS s`, then the four `LEFT JOIN`s of T006 and T007;
  - columns, in exactly this order (FR-002): `coalesce(t.sk_tempo, -1) AS sk_tempo`,
    `coalesce(c.sk_codigos, -1) AS sk_codigos`, `coalesce(k.sk_curso, -1) AS sk_curso`,
    `coalesce(u.sk_usuario, -1) AS sk_usuario`, `s.valor_desconto`, `s.valor_pago`;
  - no other column (FR-010).

**Checkpoint**: the measures and grain are written. Validation is T009, after US2 and US3
complete the joins.

---

## Phase 4: User Story 2 - Every row points to a dimension row (Priority: P1)

**Goal**: four filled keys that exist in their dimensions.

**Independent Test**: quickstart step 3, with the star join returning 420,472 rows.

- [ ] T006 [US2] In `src/pipeline/03_gold/07_fato_venda.sql`, add the date, user and course
  lookups (research, Decisions 4 and 5).
  - **CTE `versoes_curso`**, placed after `vendas`:

    ```sql
    SELECT sk_curso, curso_uuid, __START_AT, __END_AT,
           min(__START_AT) OVER (PARTITION BY curso_uuid) AS primeiro_inicio
    FROM workspace.gold.dim_curso
    WHERE sk_curso > 0
    ```

    Portuguese comment: "versões dos cursos, sem os membros".
  - **Date and user joins** in the final `SELECT`:
    - `LEFT JOIN workspace.gold.dim_tempo AS t ON t.data = CAST(s.data_venda AS DATE)`;
    - `LEFT JOIN workspace.gold.dim_usuario AS u ON u.usuario_uuid = s.usuario_uuid`.
  - **Course join**:

    ```sql
    LEFT JOIN versoes_curso AS k
      ON k.curso_uuid = s.curso_uuid
     AND (
           (s.data_venda >= k.__START_AT AND (k.__END_AT IS NULL OR s.data_venda < k.__END_AT))
        OR (s.data_venda < k.primeiro_inicio AND k.__START_AT = k.primeiro_inicio)
         )
    ```

    Portuguese comment: "versão em vigor na data da venda; venda anterior à primeira versão
    usa a primeira versão; nunca só __END_AT IS NULL".

**Checkpoint**: the key lookups are written.

---

## Phase 5: User Story 3 - Sale codes, with "Não se aplica" for file sales (Priority: P1)

**Goal**: each sale's code row, with `Não se aplica` as the location of file sales.

**Independent Test**: quickstart step 4. `ARQUIVO` appears only with `Não se aplica`
(200,000); `API` with `Desconhecido` has 2,174 sales.

- [ ] T007 [US3] In `src/pipeline/03_gold/07_fato_venda.sql`, complete the codes
  (research, Decision 3).
  - In CTE `vendas`:
    - `CASE WHEN v.origem = 'ARQUIVO' THEN 'Não se aplica' ELSE coalesce(a.local_acesso, 'Desconhecido') END AS local_acesso`;
    - `coalesce(v.forma_pagamento, 'Desconhecido') AS forma_pagamento`;
    - `coalesce(v.percentual_desconto, 'Não se aplica') AS percentual_desconto`.
  - In the final `SELECT`:

    ```sql
    LEFT JOIN workspace.gold.dim_codigos AS c
      ON c.origem_usuario = s.origem_usuario
     AND c.local_acesso = s.local_acesso
     AND c.forma_pagamento = s.forma_pagamento
     AND c.percentual_desconto = s.percentual_desconto
    ```

  - Portuguese comment: "mesmas regras de dim_codigos; venda de ARQUIVO não tem acesso:
    Não se aplica".
- [ ] T008 [US3] Upload `src/pipeline` and confirm the workspace copy is identical. Run a dry
  run and expect `COMPLETED`. Then start an update (not a full refresh) and expect
  `COMPLETED`, with `fato_venda` created as `STREAMING_TABLE`
  (`databricks tables get workspace.gold.fato_venda`) and no failed flow. Record the update
  id. On failure, fix and repeat; never refresh.

**Checkpoint**: the fact exists. Validate each story next.

---

## Validation per story

- [ ] T009 [US1] Run quickstart step 2.
  - `linhas_fato` 420,472 = `linhas_silver`;
  - `dif_pago` 0.00 and `dif_desconto` 0.00, against T001's sums;
  - `DESCRIBE workspace.gold.fato_venda` lists exactly `sk_tempo`, `sk_codigos`,
    `sk_curso` and `sk_usuario` as `bigint`, then `valor_desconto` and `valor_pago` as
    `decimal(9,2)`;
  - `SHOW TBLPROPERTIES workspace.gold.fato_venda ('quality')` returns `gold`.
- [ ] T010 [US2] Run quickstart step 3 and step 5.
  - **Step 3**: `vazias` 0, `tempo_desconhecido` 0, `codigos_desconhecido` 0,
    `curso_desconhecido` 0, `usuario_desconhecido` 4,362, `cursos` 3, `combinacoes` 22.
    The star join returns 420,472 rows.
  - **Step 5**: 3 course rows, each the course's only version, adding up to 420,472.
  - **Cross-check** of the user `-1` count against silver:
    `SELECT count(*) FROM workspace.silver.tb_venda v LEFT ANTI JOIN workspace.gold.dim_usuario u ON u.usuario_uuid = v.usuario_uuid`
    = 4,362.
- [ ] T011 [US3] Run quickstart step 4.
  - `ARQUIVO` appears only with `Não se aplica`, 200,000 sales;
  - `API` never appears with `Não se aplica`;
  - `API` with `Desconhecido` has 2,174 sales.

  Cross-check the 2,174:
  `SELECT count(*) FROM workspace.silver.tb_venda v LEFT ANTI JOIN workspace.silver.tb_acesso a ON a.acesso_uuid = v.acesso_uuid WHERE v.origem = 'API'`
  = 2,174.

**Checkpoint**: all three stories are proven.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: stability, documentation and final checks.

- [ ] T012 Record
  `count(*), sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))`
  of `workspace.gold.fato_venda`.
  - At least 4 minutes after T008, run an ordinary update with no change and expect
    `COMPLETED`.
  - Repeat the query; both values must be identical.
  - In the event log, the fact's flow reads 0 new rows, so no sale is processed twice.
- [ ] T013 [P] In `doc/pipeline-reference.md`:
  - **`### fato_venda`**:
    - change the status from "Planned (feature 013)" to "As built";
    - add the counts on 2026-11-05: 420,472 rows; sums equal to silver's;
      `sk_usuario = -1` for 4,362; 2,174 site sales with location `Desconhecido`;
      200,000 file sales on `Não se aplica`; 3 course versions and 22 code combinations
      used; no other `-1`;
    - add that the demo's course update and delete leave existing sales on the first
      version: sales already written are not reprocessed.
  - **Intro paragraph**: add `fato_venda` to the list of Gold sections that describe the
    pipeline as built.
- [ ] T014 [P] In `doc/known-issues.md`, delete the whole `## Sales missing from fato_venda`
  section: fixed by feature 013, which uses `LEFT JOIN`s and the `-1` member.
  - Keep any sentence about `obt_acesso`'s left join that still applies, moved to
    "Smaller items" as one bullet: "`obt_acesso` (earlier pipeline) still uses a left join
    for access rows; to be rebuilt".
- [ ] T015 [P] In `doc/architecture.md`, features table:
  - remove [04_fato_vendas.sql](../code_tips/03_gold/04_fato_vendas.sql) from the
    "Materialized views" row;
  - add a row "Fact as a streaming table with stream-static lookups (`LEFT JOIN`, `-1`
    fallback; SCD 2 version in effect at the event)" pointing to
    [07_fato_venda.sql](../src/pipeline/03_gold/07_fato_venda.sql).
- [ ] T016 [P] In `doc/README.md`:
  - under `03_gold/`, add
    `07_fato_venda.sql            Sales fact: streaming table over tb_venda, stream-static LEFT JOIN lookups with -1`
    as the last entry, moving the `└──` from `06_dim_curso.sql`;
  - in "Pipeline datasets", gold becomes "3 streaming views, 3 streaming tables and 1
    materialized view".
- [ ] T017 Final validation:
  - the workspace `03_gold` holds `01_` through `07_`, each identical to the repository;
  - rerun quickstart steps 2 and 3;
  - step 6 counts are equal to T001;
  - the pipeline is `IDLE`;
  - stop the warehouse with `--no-wait`.
- [ ] T018 Constitution review of `src/pipeline/03_gold/07_fato_venda.sql`:
  - `CREATE OR REFRESH STREAMING TABLE`;
  - `STREAM(...)` only on `workspace.silver.tb_venda`, which is on the left of every join;
  - no inner `JOIN`, only `LEFT JOIN`;
  - no `__END_AT IS NULL` filter on the course lookup;
  - no constraints, no `CLUSTER BY` / `PARTITIONED BY`, no legacy syntax;
  - three-level names;
  - exactly 6 output columns;
  - comments in Portuguese.

  Record the outcome, the update ids and the counts in an "Implementation Notes" section at
  the end of this file.

---

## Dependencies & Execution Order

- **Phase 1 → T002 (grain doc) → T003 → T004 → T005 → T006 → T007 → T008 → T009–T011 → T012 → T013–T016 → T017 → T018.**
- T002 MUST precede T008: the grain is documented before the build.
- T003–T007 edit one file and stay sequential.
- T009, T010 and T011 are read-only queries on the same result. They can run in any order
  after T008.
- T013–T016 touch different files and can run in parallel after T012.

### Parallel opportunities

```text
After T008:   T009 (US1), T010 (US2), T011 (US3), as read-only queries
After T012:   T013 (pipeline-reference), T014 (known-issues), T015 (architecture), T016 (README)
```

## Implementation Strategy

1. **Foundation**: T001–T003. Baseline counts, the documented grain, the declaration.
2. **Query**: T004–T007. Sales and measures (US1), key lookups (US2), codes with the
   `ARQUIVO` rule (US3).
3. **Build and prove**: T008–T011. One update, then each story's checks.
4. **Polish**: T012 (stability update), docs, final checks, constitution review.

Pipeline time: two updates, at least 4 minutes apart.
