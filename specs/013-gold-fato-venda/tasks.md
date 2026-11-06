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

- [X] T001 Confirm the preconditions:
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

- [X] T002 Rewrite `### fato_venda` in `doc/pipeline-reference.md` **before** any upload
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
- [X] T003 Create `src/pipeline/03_gold/07_fato_venda.sql` with:
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

- [X] T004 [US1] In `src/pipeline/03_gold/07_fato_venda.sql`, write CTE `vendas`
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
- [X] T005 [US1] Write the final `SELECT` in `src/pipeline/03_gold/07_fato_venda.sql`:
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

- [X] T006 [US2] In `src/pipeline/03_gold/07_fato_venda.sql`, add the date, user and course
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

- [X] T007 [US3] In `src/pipeline/03_gold/07_fato_venda.sql`, complete the codes
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
- [X] T008 [US3] Upload `src/pipeline` and confirm the workspace copy is identical. Run a dry
  run and expect `COMPLETED`. Then start an update (not a full refresh) and expect
  `COMPLETED`, with `fato_venda` created as `STREAMING_TABLE`
  (`databricks tables get workspace.gold.fato_venda`) and no failed flow. Record the update
  id. On failure, fix and repeat; never refresh.

**Checkpoint**: the fact exists. Validate each story next.

---

## Validation per story

- [X] T009 [US1] Run quickstart step 2.
  - `linhas_fato` 420,472 = `linhas_silver`;
  - `dif_pago` 0.00 and `dif_desconto` 0.00, against T001's sums;
  - `DESCRIBE workspace.gold.fato_venda` lists exactly `sk_tempo`, `sk_codigos`,
    `sk_curso` and `sk_usuario` as `bigint`, then `valor_desconto` and `valor_pago` as
    `decimal(9,2)`;
  - `SHOW TBLPROPERTIES workspace.gold.fato_venda ('quality')` returns `gold`.
- [X] T010 [US2] Run quickstart step 3 and step 5.
  - **Step 3**: `vazias` 0, `tempo_desconhecido` 0, `codigos_desconhecido` 0,
    `curso_desconhecido` 0, `usuario_desconhecido` 4,362, `cursos` 3, `combinacoes` 22.
    The star join returns 420,472 rows.
  - **Step 5**: 3 course rows, each the course's only version, adding up to 420,472.
  - **Cross-check** of the user `-1` count against silver:
    `SELECT count(*) FROM workspace.silver.tb_venda v LEFT ANTI JOIN workspace.gold.dim_usuario u ON u.usuario_uuid = v.usuario_uuid`
    = 4,362.
- [X] T011 [US3] Run quickstart step 4.
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

- [X] T012 Record
  `count(*), sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))`
  of `workspace.gold.fato_venda`.
  - At least 4 minutes after T008, run an ordinary update with no change and expect
    `COMPLETED`.
  - Repeat the query; both values must be identical.
  - In the event log, the fact's flow reads 0 new rows, so no sale is processed twice.
- [X] T013 [P] In `doc/pipeline-reference.md`:
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
- [X] T014 [P] In `doc/known-issues.md`, delete the whole `## Sales missing from fato_venda`
  section: fixed by feature 013, which uses `LEFT JOIN`s and the `-1` member.
  - Keep any sentence about `obt_acesso`'s left join that still applies, moved to
    "Smaller items" as one bullet: "`obt_acesso` (earlier pipeline) still uses a left join
    for access rows; to be rebuilt".
- [X] T015 [P] In `doc/architecture.md`, features table:
  - remove [04_fato_vendas.sql](../code_tips/03_gold/04_fato_vendas.sql) from the
    "Materialized views" row;
  - add a row "Fact as a streaming table with stream-static lookups (`LEFT JOIN`, `-1`
    fallback; SCD 2 version in effect at the event)" pointing to
    [07_fato_venda.sql](../src/pipeline/03_gold/07_fato_venda.sql).
- [X] T016 [P] In `doc/README.md`:
  - under `03_gold/`, add
    `07_fato_venda.sql            Sales fact: streaming table over tb_venda, stream-static LEFT JOIN lookups with -1`
    as the last entry, moving the `└──` from `06_dim_curso.sql`;
  - in "Pipeline datasets", gold becomes "3 streaming views, 3 streaming tables and 1
    materialized view".
- [X] T017 Final validation:
  - the workspace `03_gold` holds `01_` through `07_`, each identical to the repository;
  - rerun quickstart steps 2 and 3;
  - step 6 counts are equal to T001;
  - the pipeline is `IDLE`;
  - stop the warehouse with `--no-wait`.
- [X] T018 Constitution review of `src/pipeline/03_gold/07_fato_venda.sql`:
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

---

## Implementation Notes (2026-11-05)

**T001**: pipeline `IDLE`; `fato_venda` absent; workspace `03_gold` held `01_`–`06_`.
Baseline:

| Dataset | Rows |
|---|---|
| `tb_venda` | 420,472 |
| `tb_acesso` | 2,516,192 |
| `dim_tempo` | 3,654 |
| `dim_usuario` | 941,236 |
| `dim_codigos` | 62 |
| `dim_curso` | 5 |

- Silver sums: `valor_pago` 538,722,841.07, `valor_desconto` 33,549,457.70.
- `acesso_uuid` duplicates in `tb_acesso`: 0.
- `tb_venda` history operations: `STREAMING UPDATE`, `DLT SETUP`, `CREATE TABLE`,
  `SET TBLPROPERTIES` and one `DLT REFRESH` (an earlier full refresh of silver). No
  `DELETE`, `UPDATE` or `MERGE`, so the table is append-only.

**T002**: `### fato_venda` in `doc/pipeline-reference.md` rewritten before the upload, with
grain, keys, measures, reconciliation, keys resolved once and query joins.

**T003–T007**: `src/pipeline/03_gold/07_fato_venda.sql` written. The CTE form over
`STREAM(workspace.silver.tb_venda)` was accepted, so no inline fallback was needed.

**T008**: upload identical. Dry run `18aaaebf` **COMPLETED**. Update
`17a73045-61f7-48c4-839d-4c8d1e92ec58` **COMPLETED** (ordinary). `fato_venda` is a
`STREAMING_TABLE`.

**T009**: `linhas_fato` 420,472 = `linhas_silver`; `dif_pago` 0.00; `dif_desconto` 0.00.
`DESCRIBE`: `sk_tempo`, `sk_codigos`, `sk_curso` and `sk_usuario` are `bigint`, then
`valor_desconto` and `valor_pago` are `decimal(9,2)`. `quality` = `gold`. Exactly 6 columns.

**T010**: `vazias` 0, `tempo_desconhecido` 0, `codigos_desconhecido` 0, `curso_desconhecido`
0, `usuario_desconhecido` 4,362, `cursos` 3, `combinacoes` 22.
- The star join with inner joins returns 420,472.
- Courses:

  | Course | Sales |
  |---|---|
  | Construindo um Data Lakehouse com SQL e DLT | 135,659 |
  | Mastering SQL no Databricks | 114,942 |
  | Programa Data Heroes | 169,871 |

  Total 420,472. Each sale is on its course's only version (`__START_AT`
  2026-10-11 22:42:09.713, open), through the first-version fallback.
- Cross-check: the anti join of `tb_venda` against `dim_usuario` gives 4,362.

**T011**: codes by origin and location:

| Origin | Location | Sales |
|---|---|---|
| API | Computador | 102,148 |
| API | Desconhecido | 2,174 |
| API | Mobile | 113,846 |
| API | unknown | 2,304 |
| ARQUIVO | Não se aplica | 200,000 |

`API` never appears with `Não se aplica`. Cross-check: API sales without an access row,
2,174.

**T012**: before, 420,472 rows and checksum 736219987002. Update
`50cd5af3-5689-4873-9fdb-9eadbf2b31ca` **COMPLETED**, with no change. After, the same 420,472
and 736219987002. The fact's flow progress shows no output rows, so no sale was processed
twice.

**T013–T016**: documentation updated.
- `pipeline-reference.md`: status "As built", the counts, the demo note and the intro.
- `known-issues.md`: "Sales missing from fato_venda" removed; an `obt_acesso` bullet added
  under "Smaller items".
- `architecture.md`: the old fact removed from the materialized-views row; a streaming-fact
  row added.
- `README.md`: layout and gold count (3 streaming views, 3 streaming tables, 1 materialized
  view).

**T017**: all seven `03_gold` files are identical in the workspace. Counts are unchanged from
T001, and `fato_venda` has 420,472 rows. The pipeline is `IDLE`; the warehouse is stopped.

**T018**: `CREATE OR REFRESH STREAMING TABLE`.
- `STREAM(` appears once, on `workspace.silver.tb_venda`, on the left of every join.
- 5 `LEFT JOIN`s (`tb_acesso` and the four dimensions) and no inner join.
- `__END_AT IS NULL` appears only inside the in-effect condition (`k.__END_AT IS NULL OR …`),
  never as a filter for the current version.
- No constraints, `CLUSTER BY`, `PARTITIONED BY`, legacy syntax or `CREATE OR REPLACE`.
- Three-level names, 6 output columns, comments in Portuguese.

No full refresh or table drop was run.

---

## Revision 2026-11-06: inner joins to the dimensions

**Input**: spec Clarifications 2026-11-06 (access lookup stays a left join from the sales;
the four dimension lookups become inner joins; course rule made total), plan "Revision
(2026-11-06)", research Decisions 2, 4, 5, 9 and 10, quickstart step 0.

**Organization**: one file changes, `src/pipeline/03_gold/07_fato_venda.sql`. The change
belongs to US2 (every row points to a dimension row); US1 and US3 are re-validated because
their parts of the query run in the same statement. One ordinary update applies it: run as a
batch, the new query yields the stored rows unchanged (research, Decision 10). **No full
refresh.** The conventions at the top of this file apply.

## Phase 7: Setup (revision)

- [X] T019 Confirm the preconditions and record them in the Implementation Notes under a new heading "Revision 2026-11-06":
  - pipeline `8d51ac7a-02be-4ce2-8afd-f4f263e448dd` is `IDLE`;
  - `src/pipeline/03_gold/07_fato_venda.sql` is identical to the workspace copy (`cmp` of the export);
  - baseline counts: `tb_venda` 420,472, `fato_venda` 420,472, `dim_tempo` 3,654, `dim_usuario` 956,251, `dim_codigos` 62, `dim_curso` 5;
  - baseline checksum `sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))` of `fato_venda` = 581165462078.
  If a count or the checksum differs, stop and report it to the owner.

## Phase 8: Foundational (revision) — coverage gate

**Blocks Phase 9.** Constitution v3.1.0, Principle V: an inner join is accepted only after an anti join of the source against the dimension returns 0.

- [X] T020 Run quickstart.md step 0 against the current data (the CTE `vendas` of `src/pipeline/03_gold/07_fato_venda.sql` without `STREAM`, and `versoes_curso` with `proximo_inicio` and `primeiro_inicio`):
  - the four anti joins (`dim_tempo`, `dim_codigos`, `versoes_curso` with the new course rule, `dim_usuario`) each return 0;
  - the full new query run as a batch returns 420,472 rows and checksum 581165462078.
  Record the five results. **If any differs, stop**: the change would drop or move sales; report to the owner.

## Phase 9: User Story 2 - Every row points to a dimension row (Priority: P1)

**Goal**: the four dimension lookups are inner joins with proven coverage, and the course rule always finds one version.

**Independent Test**: quickstart.md step 3 (no key below 0, star join 420,472, checksum unchanged) and step 5.

- [X] T021 [US2] Change `src/pipeline/03_gold/07_fato_venda.sql`, keeping the CTE `vendas` and its `LEFT JOIN workspace.silver.tb_acesso` unchanged:
  - **Header comment (Portuguese)**: replace the `LEFT JOIN … -1 … Não há inner join` lines. State that:
    - the four dimensions use inner joins (Kimball), because each covers every sale: the calendar 2021–2030, every code combination, every course's version through the course rule, and every user since 2026-11-06; coverage was verified by anti join = 0 before the change (constitution v3.1.0, Princípio V);
    - the access lookup stays a `LEFT JOIN` from the sales, so only accesses that ended in a purchase are read, and the file sales and site sales without an access stay in the fact;
    - the course rule: a version is valid from its `__START_AT` until the next version's `__START_AT`; a sale older than the first version takes the first version; never only `__END_AT IS NULL`;
    - keys are resolved once; a dimension row that arrived in a later update would drop the sale under the inner join, and the row-count check after each load would show it.
  - **Comment above `vendas`**: say that the left join reads only the accesses of sales.
  - **CTE `versoes_curso`**: `SELECT sk_curso, curso_uuid, __START_AT, lead(__START_AT) OVER (PARTITION BY curso_uuid ORDER BY __START_AT) AS proximo_inicio, min(__START_AT) OVER (PARTITION BY curso_uuid) AS primeiro_inicio FROM workspace.gold.dim_curso WHERE sk_curso > 0` (drop `__END_AT`).
  - **Final `SELECT`**: `t.sk_tempo`, `c.sk_codigos`, `k.sk_curso`, `u.sk_usuario`, `s.valor_desconto`, `s.valor_pago`, in that order, with no `coalesce`.
  - **Joins**: replace each of the four `LEFT JOIN`s with `JOIN`, with the same keys. The course condition becomes `k.curso_uuid = s.curso_uuid AND ((k.__START_AT <= s.data_venda AND (k.proximo_inicio IS NULL OR s.data_venda < k.proximo_inicio)) OR (s.data_venda < k.primeiro_inicio AND k.__START_AT = k.primeiro_inicio))`, with its Portuguese comment updated to the new rule.
  - Nothing else changes: same table name, `COMMENT`, `TBLPROPERTIES ("quality" = "gold")`, `STREAM(workspace.silver.tb_venda)`.
- [X] T022 [US2] Upload, compare, dry run, then an ordinary update, following the conventions:
  - upload with `import-dir --overwrite`, then `cmp` the exported `03_gold/07_fato_venda.sql`: no difference;
  - dry run `--validate-only` to `COMPLETED`. If it rejects the window functions in the static CTE or the inner join to a stream, record the error and stop to ask the owner; do not fall back to left joins on your own;
  - at least 4 minutes later, an ordinary update (no `--full-refresh`, no `full_refresh_selection`) to `COMPLETED`; record both update ids.
- [X] T023 [US2] Run quickstart.md step 3 and step 5 for the update of T022:
  - `vazias` 0; `tempo_membro`, `codigos_membro`, `curso_membro`, `usuario_membro` each 0; `cursos` 3; `combinacoes` 22;
  - star join with inner joins to the four dimensions = 420,472;
  - checksum = 581165462078 (unchanged; the stored sales were not reprocessed);
  - step 5: 3 rows, one per course, each its only version, totalling 420,472.

## Phase 10: Re-validation of US1 and US3

- [X] T024 [P] [US1] Run quickstart.md step 2 for the update of T022: `linhas_fato` = `linhas_silver` = 420,472; `dif_pago` and `dif_desconto` 0.00 (SC-001, SC-002)
- [X] T025 [P] [US3] Run quickstart.md step 4 for the update of T022: `ARQUIVO` only with `Não se aplica` (200,000); `API` never with `Não se aplica`; `API` with `Desconhecido` 2,174 (SC-004, SC-005)

## Phase 11: Polish (revision)

- [X] T026 At least 4 minutes after T022, run a second ordinary update with no code change. Confirm `fato_venda` stays 420,472 rows with checksum 581165462078, and that `dim_usuario` 956,251, `dim_codigos` 62, `dim_curso` 5, `dim_tempo` 3,654, `tb_venda` 420,472 and `tb_acesso` 2,516,192 are unchanged (quickstart step 6). Stop the warehouse with `--no-wait`
- [X] T027 [P] Update `doc/pipeline-reference.md`:
  - **`### fato_venda`**:
    - the column table: drop "no match → `-1`" from the four keys; `sk_curso` uses the new course rule (valid until the next version's `__START_AT`; first version for older sales);
    - **Reconciliation**: the four dimension lookups are inner joins with coverage proven by anti join = 0 (2026-11-06; constitution v3.1.0, Principle V), and the access lookup is a `LEFT JOIN` from the sales;
    - **Keys resolved once**: a late dimension row would drop the sale, caught by the row-count check;
    - the 2026-11-05 results: `sk_usuario = -1` for 0 sales since 2026-11-06, and no key below 0, with the update id of T022. Line 507 is also listed in feature 006's T031; whichever runs first updates it, and the other only confirms.
  - Line 346 (`dim_tempo`, "Use by facts") and line 415 (`dim_curso`, "Current version"): a fact uses an inner join; the course rule is the one above.
- [X] T028 [P] Update `doc/architecture.md` line 135 (features table: "stream-static lookups, inner joins to the dimensions with proven coverage, `LEFT JOIN` to the accesses; SCD 2 version in effect at the event"), `doc/README.md` line 53 (`07_fato_venda.sql`: "stream-static inner joins to the dimensions") and `doc/known-issues.md` lines 21–22 (`fato_venda` does not drop sales: the dimension lookups are inner joins with proven coverage, and the access lookup is a left join)
- [X] T029 Final review: `07_fato_venda.sql` identical in the workspace; no `coalesce(` and no `LEFT JOIN workspace.gold.` left in it; the documents of T027 and T028 contain no "`LEFT JOIN` … `-1`" statement about `fato_venda`; record the summary in the Implementation Notes

### Dependencies (revision)

T019 → T020 (gate) → T021 → T022 → T023, then T024 and T025 in parallel → T026. T027 and T028 can run any time after T022, in parallel. T029 last.

### Implementation strategy (revision)

Gate first: no code changes before T020 passes. Then a single code change and one ordinary update. The stored rows don't move, so the change is safe to apply incrementally.

## Implementation Notes: Revision 2026-11-06

**T019**: pipeline `IDLE`; `07_fato_venda.sql` identical in the workspace. Baseline:
`tb_venda` 420,472, `fato_venda` 420,472, `dim_tempo` 3,654, `dim_usuario` 956,251,
`dim_codigos` 62, `dim_curso` 5, `tb_acesso` 2,516,192; fact checksum 581165462078.

**T020** (coverage gate): anti joins of the sales against `dim_tempo`, `dim_codigos`,
`versoes_curso` (new course rule) and `dim_usuario` all 0; no `curso_uuid` absent from
`dim_curso`. Sales run from 2024-06-01 to 2025-12-23, and the calendar from 2021-01-01 to
2030-12-31. The new query as a batch gives 420,472 rows and checksum 581165462078, equal to
the stored fact. The course rule was also tested on synthetic versions (before the first,
in v1, in v2, after a delete, in v3 after a re-insert): exactly one match each.

**T021**: `07_fato_venda.sql` now has inner joins to the four dimensions, `versoes_curso` with
`proximo_inicio` (`lead`) and `primeiro_inicio`, no `coalesce` on the keys, and the access
`LEFT JOIN` unchanged. The header and comments were rewritten in Portuguese.

**T022**: upload identical; dry run `11446c10` `COMPLETED` (the window functions in the
static CTE and the inner stream-static joins were accepted); ordinary update
`69381807-9d86-4ce0-a7c2-197e1ed77a95` `COMPLETED`, with `full_refresh` false and no
selection.

**T023**: `vazias` 0; no key below 0; `cursos` 3; `combinacoes` 22; star join 420,472;
checksum 581165462078, unchanged. Step 5: Programa Data Heroes 169,871, Mastering SQL no
Databricks 114,942, Construindo um Data Lakehouse com SQL e DLT 135,659 (total 420,472),
each on its only, open version.

**T024**: 420,472 = 420,472; `dif_pago` and `dif_desconto` 0.00.

**T025**: `ARQUIVO` / `Não se aplica` 200,000; `API` / `Desconhecido` 2,174; `API` /
`Não se aplica` 0.

**T026**: second update `e512631c-52db-4930-b838-587564b292b7` `COMPLETED`; `fato_venda` 420,472
with checksum 581165462078, and every other count unchanged. Warehouse stop requested.

**T027, T028**: `doc/pipeline-reference.md` (`### fato_venda`: columns, reconciliation with
the four coverage guarantees, keys resolved once, the 2026-11-06 results; `dim_tempo` "Use by
facts"; `dim_curso` "Current version"), `doc/architecture.md`, `doc/README.md` and
`doc/known-issues.md`. The `### fato_venda` results paragraph (feature 006's T031, line 507)
is done here. Feature 006's T031 still owns the other lines it lists (`tb_venda` "Keys that
do not join", the `dim_usuario` section).

**T029**: the workspace copy is identical. No `LEFT JOIN workspace.gold.` is left in the fact.
Three `coalesce(` calls remain in the CTE `vendas`: they are the sale codes' defaults
(`Desconhecido` / `Não se aplica`, FR-008), not key fallbacks. The documents of T027 and T028
no longer describe `fato_venda` with `LEFT JOIN` and `-1`.
