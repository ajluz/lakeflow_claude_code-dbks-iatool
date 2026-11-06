# Research: Gold Junk Dimension of Sale Codes

**Feature**: [spec.md](spec.md) | **Date**: 2026-11-05, revised the same day

Sources: constitution v2.0.0; `databricks-pipelines` skill, `materialized-view-sql.md`
(identity not supported; incremental refresh rules) and `sql-basics.md`; feature 009
(`dim_usuario`, the key expression); `doc/pipeline-reference.md` (`tb_venda`,
`tb_acesso`, the earlier `dim_codigos`); `doc/known-issues.md`; the workspace on
2026-11-05.

**Revision**: the first version built the combinations from the sales with a `LEFT JOIN`
(22 rows). The owner directed that a junk dimension hold every possible combination
through a cross join (spec, Clarifications). Decisions 3 to 5 and 8 changed.

No item of the Technical Context was left as NEEDS CLARIFICATION.

## Decision 1: A materialized view in the pipeline

- **Decision**: `workspace.gold.dim_codigos` is a materialized view in
  `src/pipeline/03_gold/03_dim_codigos.sql`, reading `workspace.silver.tb_venda` and
  `workspace.silver.tb_acesso` without `STREAM`.
- **Rationale**: the dimension is computed from the full set of values in two growing
  tables: a full-scan result, which the constitution places in a gold materialized view
  (Principle V). It picks up new values on every update (FR-008). The owner chose to build
  it in the pipeline (spec, Clarifications).
- **Alternatives considered**: a streaming table (SQL streaming cannot build a distinct
  cross product); a script like `04_dim_tempo.sql` (not static data, Principle I; rejected
  by the owner).

## Decision 2: The key

- **Decision**: `sk_codigos = xxhash64(origem_usuario, local_acesso, forma_pagamento,
  percentual_desconto) & 9223372036854775807`, computed on the four final codes.
- **Rationale**: deterministic, so a combination has the same key on every update and
  after any recomputation (FR-004, FR-005), including when a new code value adds rows.
  It is the `dim_usuario` expression (feature 009) applied to the four codes. `xxhash64`
  takes several arguments and hashes the tuple, so no delimiter is needed. The mask clears
  the sign bit, so real keys are never negative and only the members are.
- **Collisions**: 64 bits over a few dozen rows; uniqueness is still checked by query. A
  key of exactly 0 is possible in principle (probability 2⁻⁶³); the quickstart checks
  that every real key is positive.
- **Alternatives considered**: an identity column (not supported on materialized views;
  rejected in Clarifications); `row_number()` (reassigns keys whenever a value is added,
  which a cross product makes certain).

## Decision 3: Cross join of the value lists, not of the tables

- **Decision**: four small lists, each a `SELECT DISTINCT` over one column, crossed with
  `CROSS JOIN`:

  | List | Source | Values on 2026-11-05 |
  |---|---|---|
  | `origens` | `DISTINCT origem` of `tb_venda` | `API`, `ARQUIVO` |
  | `locais` | `DISTINCT local_acesso` of `tb_acesso`, `UNION` the literal `Desconhecido` | `Mobile`, `Computador`, `unknown`, `Desconhecido` |
  | `formas` | `DISTINCT coalesce(forma_pagamento, 'Desconhecido')` of `tb_venda` | `boleto`, `credito`, `pix` |
  | `descontos` | `DISTINCT coalesce(percentual_desconto, 'Não se aplica')` of `tb_venda` | `0%`, `5%`, `10%`, `15%` |

  Then the `ARQUIVO` rule of Decision 4 and a `DISTINCT` over the result.
- **Rationale**: a junk dimension holds every possible combination, so a future sale
  always finds its row (owner, spec Clarifications; FR-003). Crossing the lists costs 2 ×
  4 × 3 × 4 = 96 rows before the rule and 60 after it. The earlier pipeline crossed the
  two tables themselves (about 420,000 × 2.5 million rows before `DISTINCT`), which is the
  known issue this design closes.
- **`Desconhecido` as a fixed location**: site sales whose access is not in `tb_acesso`
  (2,174 today) need this value, and no table holds it. Adding it as a literal keeps the
  list independent of a join.
- **Alternatives considered**: `LEFT JOIN` from the sales (the first version: only the 22
  combinations already used, so a new pairing of known values would miss its row);
  `tb_venda CROSS JOIN tb_acesso` then `DISTINCT` (the known issue).

## Decision 4: Code rules

| Column | Expression on the crossed lists |
|---|---|
| `origem_usuario` | `o.origem_usuario` |
| `local_acesso` | `CASE WHEN o.origem_usuario = 'ARQUIVO' THEN 'Não se aplica' ELSE l.local_acesso END` |
| `forma_pagamento` | `f.forma_pagamento` (already `coalesce`d to `Desconhecido`) |
| `percentual_desconto` | `d.percentual_desconto` (already `coalesce`d to `Não se aplica`) |

- **Rationale**: spec FR-002 and Assumptions. The `CASE` collapses the four locations of an
  `ARQUIVO` row to one, which the `DISTINCT` then deduplicates: 12 `ARQUIVO` rows instead of
  48. `API` rows never get `Não se aplica`.
- **Rules a fact applies to find its row**: the same rules on its own columns, with the
  sale's access looked up by `acesso_uuid` and `Desconhecido` when it is missing
  (contract).

## Decision 5: Members by `UNION ALL`

- **Decision**: the view's query is the 60 combinations `UNION ALL` two literal rows: `-1`
  with `Desconhecido` and `-2` with `Não se aplica` in all four codes.
- **Rationale**: a materialized view is batch, so a union with literals is valid (the
  streaming-plus-batch union that failed in feature 009 does not arise). A member never
  equals a combination, because a combination's `origem_usuario` is `API` or `ARQUIVO`.

## Decision 6: `data_carga`

- **Decision**: `current_timestamp()`: the time of the pipeline update that last wrote
  the row.
- **Rationale**: the dimension's own load time, never silver's, which is the meaning the
  owner chose for `dim_usuario` (feature 009). A non-deterministic function in the
  `SELECT` makes every refresh a full recompute (`materialized-view-sql.md`, "Incremental
  refresh"), so every row gets the time of each update. Computing four `DISTINCT` lists and
  62 rows is cheap.
- **Consequence for the spec**: FR-002 reworded to "time of the pipeline update that last
  wrote the row" (spec, Clarifications).
- **Alternatives considered**: a first-seen time from silver (silver's load time, which the
  owner excluded for `dim_usuario`).

## Decision 7: Expectations and layout

- **Decision**: no expectations (FR-010); no `CLUSTER BY` (62 rows); `TBLPROPERTIES
  ("quality" = "gold")`; a Portuguese header comment and `COMMENT`.

## Decision 8: Validation

- **Decision**: dry run, one update, the [quickstart.md](quickstart.md) queries, then a
  second update to compare every `(combination, sk_codigos)` pair.
- **Rationale**: because every update recomputes the view (Decision 6), an ordinary second
  update rebuilds every row from nothing; identical pairs after it prove SC-004's "after a
  full refresh" without running one. The quickstart also checks that every silver sale,
  with its codes computed by the rules of Decision 4, finds exactly one row (SC-003).
