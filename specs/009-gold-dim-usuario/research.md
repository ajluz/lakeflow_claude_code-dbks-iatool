# Research: Gold User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

Sources consulted: constitution v1.11.0 (Principles I, III, V, VII; Constraints); the
`databricks-pipelines` skill (`references/materialized-view-sql.md`,
`expectations-sql.md`); feature 006 (`tb_usuario`); `doc/known-issues.md`; the pipeline's
settings; queries on the workspace (profile `databricks-free`) on 2026-10-28.

## Facts established

| Fact | Value (2026-10-28) |
|---|---|
| `silver.tb_usuario` | 941,234 rows, 941,234 distinct `usuario_uuid`, none empty; `API` 741,234, `ARQUIVO` 200,000; every age present; 29,599 emails without `@` |
| Users referenced by `tb_venda` but absent from `tb_usuario` | 4,362 (their sex failed `check_sexo_usuario`) |
| Accesses without a user | 1,767,621 |
| Pipeline source | glob `.../lakeflow_dev/src/pipeline/**`; default schema `bronze`; serverless |
| `workspace.gold` | holds `dim_tempo` only |

## Decision 1: A materialized view

- **Decision**: `CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_usuario`, reading
  `workspace.silver.tb_usuario` without `STREAM`.
- **Rationale**: Principle V: a gold full-scan result is a materialized view. The
  dimension is not fed by a change feed (silver users are append-only), so the streaming
  exception for SCD type 2 dimensions does not apply.
- **Alternatives considered**: a streaming table with an append flow from `tb_usuario`
  (would keep identity values between updates, but not across a full refresh, and could
  not hold the two members without a second flow of literals).

## Decision 2: `sk_usuario = xxhash64(usuario_uuid)`

- **Decision**: the surrogate key is `xxhash64(usuario_uuid)`, a `BIGINT`.
- **Rationale**:
  - Principle VII: one column, and a value that never changes for a given user. A
    deterministic function of the business key gives the same value on every update,
    refresh and full refresh, with no state to lose.
  - The skill's `materialized-view-sql.md`: identity columns are not supported on
    materialized views, which settles the open item in `doc/known-issues.md` for this
    dimension.
  - `xxhash64` is a built-in Spark function with a fixed seed, so its value does not
    depend on the run.
- **Collision risk**: with 941,236 keys in a 64-bit space, the chance of any collision is
  about 2.4 × 10⁻⁸. Uniqueness is verified after each load (quickstart); a collision
  would fail that check, not pass silently.
- **Alternatives considered**: an identity column (not supported on a materialized view;
  reassignable); `row_number()` (changes when rows are added); the `md5` string itself
  (not a compact surrogate; the constitution separates `sk_` from `_uuid`).

## Decision 3: SCD type 1 by latest silver row

- **Decision**: `QUALIFY row_number() OVER (PARTITION BY usuario_uuid ORDER BY data_carga
  DESC) = 1` over silver.
- **Rationale**: the request says "no SCD type 2"; type 1 keeps one current row per user.
  Silver has no repeated key today, so the window changes nothing now but keeps the grain
  if silver ever appends a key twice.

## Decision 4: The two members

- **Decision**:

  | Member | `sk_usuario` | `usuario_uuid` | Text attributes | `idade_usuario` |
  |---|---|---|---|---|
  | unknown | `-1` | `'-1'` | `'Desconhecido'` | null |
  | not applicable | `-2` | `'-2'` | `'Não se aplica'` | null |

  Text attributes are `nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`,
  `profissao_usuario`, `empresa_usuario` and `origem`.
- **Rationale**: Principle VII requires both members. `-1` and `-2` are the usual Kimball
  values, are readable in a fact, and cannot be a real business key: `usuario_uuid` is a
  32-character hexadecimal `md5`. The surrogate keys `-1` and `-2` could in theory equal
  an `xxhash64` value; the uniqueness check covers that too.
- **Alternatives considered**: hashing the labels (`xxhash64('Desconhecido')`), which
  makes the member keys unreadable in facts.

## Decision 5: `data_carga`

- **Decision**: `current_timestamp() AS data_carga` on every row.
- **Rationale**: the spec defines it as the time the row was loaded into gold. Because the
  function is non-deterministic, the view is recomputed in full on each update
  (`materialized-view-sql.md`), so `data_carga` shows the last refresh. At 941,236 rows
  that costs little.
- **Alternatives considered**: carrying silver's `data_carga` (a different meaning, and
  the spec asks for the gold load time).

## Decision 6: No boundary view between silver and gold

- **Decision**: the view reads `workspace.silver.tb_usuario` directly.
- **Rationale**: Principle I's boundary views exist to drop the bronze lineage columns,
  "because only bronze carries those columns, every read of a bronze table goes through
  such a view". Silver tables carry none of them. The diagram draws `S3 → G1` with no
  view, and the target-graph rule forbids adding one.

## Decision 7: Expectations

- **Decision**: `check_sk_usuario` (`sk_usuario IS NOT NULL`) and `check_usuario_uuid`
  (`usuario_uuid IS NOT NULL`), both `ON VIOLATION FAIL UPDATE`.
- **Rationale**: Principle III reserves `FAIL UPDATE` for invariants such as a null key in
  a gold dimension. Uniqueness is not a row-level condition, so it is verified by query.
- **Expected failures**: 0.
