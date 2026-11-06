# Contract: `workspace.gold.obt_acesso`

What consumers (dashboards, Genie, analysts) may rely on.

## Schema

The 19 columns of [data-model.md](../data-model.md), in that order, with those types.

## Guarantees

| Guarantee | Detail |
|---|---|
| Grain | One row per (`local_acesso`, `endereco_ip_acesso`, `data`); no two rows share it |
| Completeness | Every access of `silver.tb_acesso` is counted once in `qtde_acesso` |
| Counts | `qtde_usuario` counts accesses with a user; `qtde_vendidos` counts site sales linked to the accesses. All three are additive |
| Calendar | The 13 calendar columns are `dim_tempo`'s for `data`, with its names and values |
| Freshness | Recomputed from its sources on every pipeline update |

## Not guaranteed

- An access or sale identifier: the table stores none, so a row cannot be traced back to
  one access without the sources.
- Sales without an access (file sales, and site sales whose access silver rejected) are not
  counted.
- `qtde_vendidos` is not revenue; amounts live in `fato_venda`.

## Producer

`src/pipeline/03_gold/08_obt_acesso.sql` (materialized view), pipeline
`lakeflow_dataslight_dev`. Reads `silver.tb_acesso`, `silver.tb_venda` and `gold.dim_tempo`.
