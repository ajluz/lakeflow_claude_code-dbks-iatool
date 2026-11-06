# Contract: `workspace.gold.dim_codigos`

What consumers (`fato_venda`, Genie, dashboards) may rely on.

## Schema

The 6 columns of [data-model.md](../data-model.md), in that order, with those types.

## Guarantees

| Guarantee | Detail |
|---|---|
| Grain | One row per possible combination of `origem_usuario`, `local_acesso`, `forma_pagamento`, `percentual_desconto`: the cross product of each code's values in silver, plus two members |
| Completeness | Every sale in silver finds a row, including combinations no earlier sale had |
| Key stability | A combination's `sk_codigos` never changes, across updates, full refreshes and the arrival of new code values |
| Key sign | Real combinations positive; `-1` = unknown, `-2` = not applicable |
| No empty codes | Every code column is filled on every row |
| Lookup | A sale computes its four codes with the rules of [research.md](../research.md), Decision 4 (access looked up by `acesso_uuid`, `Desconhecido` when missing) and matches all four; no match → `-1` |
| Labels | `Não se aplica` in `local_acesso` = file sale; `Desconhecido` = site sale without an access row; `unknown` = unrecognised device (from silver) |

## Not guaranteed

- That a row has ever been used by a sale: most combinations are possible, not observed.
- `data_carga` is the time of the latest pipeline update, not when a combination first
  appeared.
- Key order means nothing.

## Producer

`src/pipeline/03_gold/03_dim_codigos.sql`, pipeline `lakeflow_dataslight_dev`.
