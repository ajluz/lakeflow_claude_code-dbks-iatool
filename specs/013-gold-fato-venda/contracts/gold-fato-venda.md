# Contract: `workspace.gold.fato_venda`

What consumers (dashboards, Genie, `obt_acesso` later) may rely on.

## Schema

The 6 columns of [data-model.md](../data-model.md), in that order, with those types.

## Guarantees

| Guarantee | Detail |
|---|---|
| Grain | One row per sale of `silver.tb_venda`; none dropped, none duplicated |
| Reconciliation | Row count and the sums of `valor_pago` and `valor_desconto` equal silver's |
| Keys | All four keys are always filled and always exist in their dimensions; joins to the dimensions never drop rows |
| Unknown | `-1` means the lookup found nothing: a user rejected by silver, a date outside the calendar, a course with no applicable version, or a code combination missing from `dim_codigos` |
| File sales | Their code row has `local_acesso = 'Não se aplica'` |
| Course history | A sale points to the course version in effect at the sale, or the first version if the sale is older. Later course changes do not move past sales |
| Keys fixed at load | A sale's keys are resolved once, when it is processed, after the same update's dimensions. A dimension row that arrives in a later update does not change sales already written; they keep `-1` until a full refresh approved by the owner |
| Query joins | Every key exists in its dimension, so inner joins from the fact to any dimension return every row |
| Measures | Both additive across every dimension |

## Not guaranteed

- A sale identifier: the fact stores none, so a row cannot be traced back to one sale
  without the dimensions.
- `-2` (not applicable) is not used by any key today.

## Producer

`src/pipeline/03_gold/07_fato_venda.sql` (streaming table over `STREAM(silver.tb_venda)`), pipeline
`lakeflow_dataslight_dev`. Reads `silver.tb_venda`, `silver.tb_acesso`, `gold.dim_tempo`,
`gold.dim_codigos`, `gold.dim_curso` and `gold.dim_usuario`.
