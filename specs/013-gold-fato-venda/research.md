# Research: Gold Sales Fact

**Feature**: [spec.md](spec.md) | **Date**: 2026-11-05, revised the same day (constitution v3.0.0: facts are streaming tables) and on 2026-11-06 (inner joins to the dimensions; Decisions 2, 4, 5, 9 and 10)

Sources:
- constitution v2.0.0;
- `databricks-pipelines` skill: `streaming-table-sql.md` (stream-static join), `scd-2-querying.md` (the
  as-of-transaction join with `[__START_AT, __END_AT)`);
- `doc/pipeline-reference.md` (`tb_venda`, `tb_acesso`, and the four dimensions);
- `doc/known-issues.md` ("Sales missing from fato_venda");
- the earlier pipeline's `code_tips/03_gold/04_fato_vendas.sql` (git history);
- features 009–012;
- the workspace on 2026-11-05.

No item of the Technical Context was left as NEEDS CLARIFICATION.

## Decision 1: A streaming table fed from silver, with stream-static lookups (revised)

- **Decision**: `workspace.gold.fato_venda` is a streaming table in
  `src/pipeline/03_gold/07_fato_venda.sql`:
  - `CREATE OR REFRESH STREAMING TABLE ... AS SELECT ...`;
  - the source is `STREAM(workspace.silver.tb_venda)`, read incrementally;
  - `tb_acesso`, `dim_tempo`, `dim_codigos`, `dim_curso` and `dim_usuario` are read without
    `STREAM`.
- **Rationale**:
  - Constitution v3.0.0, Principle V: a fact is a streaming table fed from an append-only
    silver source, with stream-static lookups. That follows the Databricks
    dimensional-modeling guidance ("Build fact tables as streaming tables fed incrementally
    from silver").
  - `tb_venda` is append-only: it is the target of two append flows, with no `AUTO CDC`,
    updates or deletes. So it can feed the stream without `SKIPCHANGECOMMITS`.
  - Each sale is processed once. Per the skill (`streaming-table-sql.md`), the static
    sides are read as a snapshot when the stream starts in each update.
  - The fact depends on the four dimensions, so the pipeline refreshes them first in each
    update (owner's clarification).
- **Alternatives considered**:
  - A materialized view: the first plan. It is no longer allowed for facts (constitution
    v3.0.0).
  - Storing natural keys and joining at query time, as in the Databricks page's example:
    the spec and Principle VII require surrogate keys.

## Decision 2: Inner joins to the four dimensions, each with proven coverage (revised 2026-11-06)

- **Decision**: one inner `JOIN` per dimension, with the stream on the left and the
  dimension read without `STREAM`. No `coalesce`. Each dimension's coverage is guaranteed
  as follows (constitution v3.1.0, Principle V):

  | Dimension | Lookup key | Why every sale matches | Anti join on 2026-11-06 |
  |---|---|---|---|
  | `dim_tempo` | `data = CAST(data_venda AS DATE)` | the calendar covers 2021-01-01 to 2030-12-31; sales run from 2024-06-01 to 2025-12-23, and the demonstration generates no data for the past (owner) | 0 |
  | `dim_codigos` | the four codes | it holds every combination of the codes, computed with its own rules (Decision 3, feature 011) | 0 |
  | `dim_curso` | `curso_uuid` + the course rule | every sale's course has a version, and the rule always picks one (Decision 4) | 0 (and 0 `curso_uuid` absent) |
  | `dim_usuario` | `usuario_uuid` | users and sales come from the same sources, and silver drops no user since 2026-11-06 (feature 006, Phase 9) | 0 |

- **Rationale**:
  - The owner asked for Kimball's surrogate key pipeline, where every lookup succeeds
    (spec, Clarifications 2026-11-06).
  - Principle V allows it once coverage is proven by query; the four anti joins return 0.
  - After every load, the fact's row count must equal silver's. A sale that ever misses a
    dimension is a violation to fix in that dimension (quickstart, step 2).
- **Duplicates**: each lookup must match at most one row, or a sale would be multiplied.
  `dim_tempo` has one row per date, `dim_usuario` one per `usuario_uuid`, `dim_codigos` one
  per combination, and the course rule picks exactly one version (Decision 4). The access
  lookup matches at most one access (`acesso_uuid` is unique).
- **Alternatives considered**:
  - Left joins with `-1` on all four (the first build): replaced at the owner's request.
  - Inner join to `tb_acesso`: removes all 200,000 file sales and 2,174 site sales; the
    owner kept the left join (Decision 3).
  - Keeping `dim_curso` on a left join: unnecessary once the course rule is total.

## Decision 3: The sale codes, computed exactly as `dim_codigos` builds them

- **Decision**: a first CTE, `vendas`, computes one row per sale.
  - **`origem_usuario`** = `v.origem`.
  - **`local_acesso`** = `CASE WHEN v.origem = 'ARQUIVO' THEN 'Não se aplica' ELSE coalesce(a.local_acesso, 'Desconhecido') END`,
    from
    `LEFT JOIN workspace.silver.tb_acesso AS a ON v.origem = 'API' AND a.acesso_uuid = v.acesso_uuid`.
  - **`forma_pagamento`** = `coalesce(v.forma_pagamento, 'Desconhecido')`.
  - **`percentual_desconto`** = `coalesce(v.percentual_desconto, 'Não se aplica')`.
  - The CTE also carries the measures, `data_venda`, `usuario_uuid` and `curso_uuid`.
  - The fact then joins `dim_codigos` on all four codes.
- **Rationale**:
  - This is the request's rule ("Não se aplica when the origem is ARQUIVO").
  - The other rules are those of `dim_codigos` (feature 011). The same expressions
    guarantee a match, because `dim_codigos` holds every combination of these values.
  - The `v.origem = 'API'` condition makes it explicit that file sales are never looked up
    in the accesses (spec, edge cases).
  - On 2026-11-05 every sale matched a code row with these rules (feature 011, quickstart
    step 3).
- **Alternatives considered**:
  - Computing `xxhash64` of the four codes instead of joining. It gives the same key and
    no join, but it duplicates the key expression in a second file. It would also hide a
    missing combination, which the inner join exposes as a row-count difference.

## Decision 4: The course version in effect, else the first version

- **Decision** (revised 2026-11-06): a CTE `versoes_curso` over `workspace.gold.dim_curso`,
  keeping rows where `sk_curso > 0` (no members). It adds
  `lead(__START_AT) OVER (PARTITION BY curso_uuid ORDER BY __START_AT) AS proximo_inicio`
  and `min(__START_AT) OVER (PARTITION BY curso_uuid) AS primeiro_inicio`. A version is
  valid from its `__START_AT` until the next version's `__START_AT`, so the version in effect
  is the latest one that started on or before the sale.

  The fact joins it with:

  ```sql
  JOIN versoes_curso AS c
    ON c.curso_uuid = s.curso_uuid
   AND (
         (c.__START_AT <= s.data_venda AND (c.proximo_inicio IS NULL OR s.data_venda < c.proximo_inicio))
      OR (s.data_venda < c.primeiro_inicio AND c.__START_AT = c.primeiro_inicio)
       )
  ```

  `sk_curso` = `c.sk_curso`.
- **Rationale**:
  - FR-005 and the owner's two answers (spec, Clarifications).
  - The first branch is the skill's as-of-transaction join, with the window
    `[__START_AT, next __START_AT)` (start inclusive, end exclusive).
  - The second branch catches sales older than the course's first version. On 2026-11-05
    that is every sale.
  - The two branches cannot both match one sale:
    - the first needs `data_venda >= __START_AT`;
    - the second needs `data_venda <` the first `__START_AT`;
    - the windows `[__START_AT, next __START_AT)` of one course do not overlap and leave
      no gap from the first start onward.

    So each sale gets exactly one version.
  - The next version's start replaces `__END_AT` as the upper bound. When versions are
    contiguous they are the same. After a deletion (`__END_AT` set, no next version), a
    later sale takes the closed version; in a gap before a re-insertion, the version
    before the gap. Tested on 2026-11-06 with synthetic versions (before the first, in v1,
    in v2, after a delete, in v3 after a re-insert): exactly one match each.
  - So no sale resolves to `-1`, and the inner join is safe (Decision 2).
  - There is no `__END_AT IS NULL` filter (owner: not current-only).
- **Alternatives considered**:
  - Current version only (rejected by the owner).
  - Strict as-of (every sale is `-1` today).
  - The `[__START_AT, __END_AT)` window of the first build: it leaves a sale after a
    deletion without a version, which an inner join would drop.

## Decision 5: Date and user lookups

- **Decision** (revised 2026-11-06):
  - `JOIN workspace.gold.dim_tempo AS t ON t.data = CAST(s.data_venda AS DATE)`.
  - `JOIN workspace.gold.dim_usuario AS u ON u.usuario_uuid = s.usuario_uuid`.
  - No `coalesce`; coverage per Decision 2.
- **Rationale**:
  - FR-006 and FR-007.
  - The members of `dim_tempo` have an empty `data`, and those of `dim_usuario` have
    business keys `'-1'` / `'-2'`, so a real sale never matches a member.
  - `dim_tempo` is the static calendar loaded outside the pipeline (Principle I allows
    reading it).
- **Expected**:
  - `sk_tempo = -1` for 0 sales: every sale falls between 2024-06-01 and 2025-12-23, inside
    2021–2030.
  - `sk_usuario = -1` for 0 sales since 2026-11-06 (it was 4,362 while silver dropped
    users); with the inner join no key is `-1`.

## Decision 6: Columns, order and types

- **Decision**: the final `SELECT` lists `sk_tempo`, `sk_codigos`, `sk_curso`, `sk_usuario`,
  `valor_desconto`, `valor_pago`, in that order, and nothing else.
- **Rationale**:
  - FR-002 and FR-010.
  - The four keys are BIGINT in their dimensions and are taken from them unchanged.
  - The measures keep silver's `DECIMAL(9,2)`.
- **Alternatives considered**: adding `venda_uuid` or `data_carga` (not requested; spec
  Assumptions).

## Decision 7: Grain documented before the build; no expectations

- **Decision**:
  - The `### fato_venda` section of `doc/pipeline-reference.md` is rewritten with the
    grain, measures and key resolution before the first update.
  - No expectations are declared. Keys and reconciliation are checked by query.
- **Rationale**: Principle VII ("state its grain … before it is built"), FR-013,
  Principle III and FR-011.

## Decision 8: No full refresh, no drop

- **Decision**: the first ordinary update creates the streaming table and processes all
  420,472 existing sales.
- **Rationale**: `workspace.gold.fato_venda` does not exist. The gold schema holds
  `dim_tempo`, `dim_usuario`, `dim_codigos` and `dim_curso`.

## Decision 9: Keys are resolved once, when a sale is processed

- **Decision**: a sale's four keys are set when the stream first processes it. They are not
  updated later.
- **Rationale**:
  - Constitution v3.0.0 requires each fact's plan to state this.
  - The owner accepted it (spec, Clarifications): within an update the dimensions finish
    first, so a sale sees every dimension row of that update.
  - With the inner joins (2026-11-06), a dimension row that arrives in a later update than
    its sale would drop the sale, and the row-count check would report it. Only a full
    refresh approved by the owner would then bring the sale back.
  - Consequences today:
    - a dimension row arriving in a later update than its sale would now drop the sale
      under the inner join, which the row-count check reports; within one update the
      dimensions load first, so it does not happen (owner, 2026-11-05);
    - the demo's course update and delete do not touch existing sales, which matches
      FR-005 (past sales stay on the version that applied to them).
- **Alternatives considered**:
  - A materialized view that recomputes every sale: not allowed for facts.
  - A scheduled full refresh: destroys streaming state and needs approval every time.

## Decision 10: Apply the change with an ordinary update (2026-11-06)

- **Decision**: no full refresh of `fato_venda`. The changed query applies to sales
  processed from now on; the 420,472 stored rows stay.
- **Rationale**: run as a batch over all sales on 2026-11-06, the new query gives 420,472
  rows and `sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))`
  = 581165462078, exactly the stored fact's. No stored sale uses `-1`, and every sale's
  course resolves to the same version under the new rule.
- **Alternatives considered**: a full refresh of `fato_venda`: same result, but it costs a
  reprocess and the owner's approval for nothing.
