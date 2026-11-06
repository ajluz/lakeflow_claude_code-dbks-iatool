# Data Model: Gold Junk Dimension of Sale Codes

**Feature**: [spec.md](spec.md) | **Date**: 2026-11-05

## `workspace.gold.dim_codigos`

Materialized view in the pipeline, `src/pipeline/03_gold/03_dim_codigos.sql`. Grain: one
possible combination of sale codes. SCD type 1 (a row is its combination; nothing to
overwrite). `TBLPROPERTIES ("quality" = "gold")`. No expectations, no clustering.

| # | Column | Type | Combinations | `-1` | `-2` |
|---|---|---|---|---|---|
| 1 | `sk_codigos` | BIGINT | `xxhash64(<4 codes>) & 9223372036854775807`, positive | `-1` | `-2` |
| 2 | `origem_usuario` | STRING | `API` / `ARQUIVO` | `Desconhecido` | `Não se aplica` |
| 3 | `local_acesso` | STRING | `API`: `Mobile` / `Computador` / `unknown` / `Desconhecido`; `ARQUIVO`: `Não se aplica` | `Desconhecido` | `Não se aplica` |
| 4 | `forma_pagamento` | STRING | `boleto` / `credito` / `pix`; `Desconhecido` if empty | `Desconhecido` | `Não se aplica` |
| 5 | `percentual_desconto` | STRING | `0%` / `5%` / `10%` / `15%`; `Não se aplica` if empty | `Desconhecido` | `Não se aplica` |
| 6 | `data_carga` | TIMESTAMP | time of the update that last wrote the row | same | same |

Expressions: [research.md](research.md), Decisions 2 to 4.

## Sources: one value list per code

| List | Source | Read |
|---|---|---|
| `origens` | `DISTINCT origem` of `workspace.silver.tb_venda` | batch |
| `locais` | `DISTINCT local_acesso` of `workspace.silver.tb_acesso`, plus `Desconhecido` | batch |
| `formas` | `DISTINCT coalesce(forma_pagamento, 'Desconhecido')` of `tb_venda` | batch |
| `descontos` | `DISTINCT coalesce(percentual_desconto, 'Não se aplica')` of `tb_venda` | batch |

The lists are crossed (`CROSS JOIN`); the tables are never crossed with each other.

## Contents on 2026-11-05

| Part | Rows |
|---|---|
| `API`: 4 locations × 3 payment methods × 4 discounts | 48 (12 with `Desconhecido`) |
| `ARQUIVO`: 1 location × 3 × 4 | 12 |
| Members | 2 |
| **Total** | **62** |

22 of the 60 combinations are used by sales today.

## Rules (verified by query)

- `sk_codigos` unique and not null; real keys > 0, members -1 and -2.
- The four codes are never null, and unique together.
- Every `ARQUIVO` row has `local_acesso` = `Não se aplica`; no `API` row does.
- Rows = product of the list sizes after the `ARQUIVO` rule, + 2.
- Every silver sale matches exactly one row on its four codes.

## Lifecycle

| Event | Effect |
|---|---|
| Pipeline update | The view is recomputed; every row is rewritten with that update's `data_carga`; keys are the same |
| A new code value in silver | The next update crosses it with the other lists, adding rows with new keys |
| Full refresh | Same as an update: keys are recomputed from the codes and do not change |

## Relationships

None outgoing. `fato_venda` (future) will resolve `sk_codigos` by computing the same four
codes for each sale and matching on them, falling back to `-1`.
