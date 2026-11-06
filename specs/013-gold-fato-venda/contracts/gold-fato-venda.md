# Contract: `workspace.gold.fato_venda`

What consumers (dashboards, Genie, `obt_acesso` later) may rely on.

## Schema

The 6 columns of [data-model.md](../data-model.md), in that order, with those types.

## Guarantees

| Guarantee | Detail |
|---|---|
| Grain | One row per sale of `silver.tb_venda`; none dropped, none duplicated |
| Reconciliation | Row count and the sums of `valor_pago` and `valor_desconto` equal silver's |
| Keys | All four keys are always filled, never below 0, and always exist in their dimensions; joins to the dimensions never drop rows |
| Lookups | The fact is loaded with inner joins to the four dimensions, each with coverage proven by an anti join returning 0 (2026-11-06). No key uses `-1` or `-2` |
| File sales | Their code row has `local_acesso = 'Não se aplica'` |
| Course history | A sale points to the course version in effect at the sale (valid until the next version starts, so a sale after a deletion takes the closed version), or the first version if the sale is older. Later course changes do not move past sales |
| Keys fixed at load | A sale's keys are resolved once, when it is processed, after the same update's dimensions. Later dimension changes do not change sales already written |
| Query joins | Every key exists in its dimension, so inner joins from the fact to any dimension return every row |
| Measures | Both additive across every dimension |

## Not guaranteed

- A sale identifier: the fact stores none, so a row cannot be traced back to one sale
  without the dimensions.
- `-1` and `-2` are not used by any key; the members stay in the dimensions for other facts.

## Producer

`src/pipeline/03_gold/07_fato_venda.sql` (streaming table over `STREAM(silver.tb_venda)`), pipeline
`lakeflow_dataslight_dev`. Reads `silver.tb_venda`, `silver.tb_acesso`, `gold.dim_tempo`,
`gold.dim_codigos`, `gold.dim_curso` and `gold.dim_usuario`.
