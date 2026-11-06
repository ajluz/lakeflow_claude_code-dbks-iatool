# Research: Gold Sales Fact

**Feature**: [spec.md](spec.md) | **Date**: 2026-11-05, revised the same day (constitution v3.0.0: facts are streaming tables)

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

## Decision 2: Every lookup is a `LEFT JOIN` with a member fallback

- **Decision**: one `LEFT JOIN` per lookup, with the stream on the left, followed by
  `coalesce(<key>, -1)` for each of the four keys. There are no inner joins (constitution
  v3.0.0, Principle V).
- **Load joins and query joins**:
  - These `LEFT JOIN`s are load-time lookups that give every sale a valid key.
  - Queries from the fact to the dimensions then use plain inner joins, which never drop
    a sale, because every key exists. This is how Kimball's "no lost facts, no null
    foreign keys" rule is met in SQL.
- **Rationale**:
  - FR-003, FR-004 and FR-009; Principle I (facts reconcile with silver); Principle VII
    (no null foreign keys).
  - It fixes the known issue: the earlier inner joins dropped all 200,000 file sales and
    the 6,536 sales whose access or user is missing.
  - `-2` is not needed: no key is "not applicable" by nature (spec, FR-004).
- **Duplicates**: each lookup must match at most one row, or a sale would be multiplied.
  - `dim_tempo`: one row per date.
  - `dim_usuario`: one row per `usuario_uuid`.
  - `dim_codigos`: one row per combination of the four codes.
  - `tb_acesso`: `acesso_uuid` is unique; feature 011 checked that 420,472 sales stay
    420,472 after this join.
  - `dim_curso`: see Decision 4.
- **Alternatives considered**: inner joins (the defect being fixed).

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
    missing combination, which the join turns into `-1`.

## Decision 4: The course version in effect, else the first version

- **Decision**: a CTE `versoes_curso` over `workspace.gold.dim_curso`, keeping rows where
  `sk_curso > 0` (no members). It adds
  `min(__START_AT) OVER (PARTITION BY curso_uuid) AS primeiro_inicio`.

  The fact joins it with:

  ```sql
  LEFT JOIN versoes_curso AS c
    ON c.curso_uuid = s.curso_uuid
   AND (
         (s.data_venda >= c.__START_AT AND (c.__END_AT IS NULL OR s.data_venda < c.__END_AT))
      OR (s.data_venda < c.primeiro_inicio AND c.__START_AT = c.primeiro_inicio)
       )
  ```

  `sk_curso` = `coalesce(c.sk_curso, -1)`.
- **Rationale**:
  - FR-005 and the owner's two answers (spec, Clarifications).
  - The first branch is the skill's as-of-transaction join, with
    `[__START_AT, __END_AT)` (start inclusive, end exclusive).
  - The second branch catches sales older than the course's first version. On 2026-11-05
    that is every sale.
  - The two branches cannot both match one sale:
    - the first needs `data_venda >= __START_AT`;
    - the second needs `data_venda <` the first `__START_AT`;
    - versions of one course do not overlap.

    So each sale gets at most one version.
  - Cases that resolve to `-1`, as FR-005 states:
    - a sale in a gap after a deletion, before a re-insertion;
    - a sale after the course's last version closed.

    Neither exists today.
  - There is no `__END_AT IS NULL` filter (owner: not current-only).
- **Alternatives considered**:
  - Current version only (rejected by the owner).
  - Strict as-of (every sale is `-1` today).

## Decision 5: Date and user lookups

- **Decision**:
  - `LEFT JOIN workspace.gold.dim_tempo AS t ON t.data = CAST(s.data_venda AS DATE)`.
  - `LEFT JOIN workspace.gold.dim_usuario AS u ON u.usuario_uuid = s.usuario_uuid`.
  - Each key is `coalesce(..., -1)`.
- **Rationale**:
  - FR-006 and FR-007.
  - The members of `dim_tempo` have an empty `data`, and those of `dim_usuario` have
    business keys `'-1'` / `'-2'`, so a real sale never matches a member.
  - `dim_tempo` is the static calendar loaded outside the pipeline (Principle I allows
    reading it).
- **Expected**:
  - `sk_tempo = -1` for 0 sales: every sale falls between 2024-06-01 and 2025-12-23, inside
    2021–2030.
  - `sk_usuario = -1` for 4,362 sales.

## Decision 6: Columns, order and types

- **Decision**: the final `SELECT` lists `sk_tempo`, `sk_codigos`, `sk_curso`, `sk_usuario`,
  `valor_desconto`, `valor_pago`, in that order, and nothing else.
- **Rationale**:
  - FR-002 and FR-010.
  - The four keys are BIGINT in their dimensions, and `coalesce` with the literal `-1`
    keeps them BIGINT.
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
  - A dimension row that arrives in a later update than its sale leaves the sale at `-1`.
    Only a full refresh approved by the owner resolves it again.
  - Consequences today:
    - the 4,362 sales whose user silver rejects stay `-1`, which is correct anyway;
    - the demo's course update and delete do not touch existing sales, which matches
      FR-005 (past sales stay on the version that applied to them).
- **Alternatives considered**:
  - A materialized view that recomputes every sale: not allowed for facts.
  - A scheduled full refresh: destroys streaming state and needs approval every time.
