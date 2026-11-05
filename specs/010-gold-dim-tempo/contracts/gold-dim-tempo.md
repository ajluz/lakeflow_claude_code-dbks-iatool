# Contract: `workspace.gold.dim_tempo`

What consumers (future facts, Genie, dashboards) may rely on.

## Schema

The 16 columns of [data-model.md](../data-model.md), in that order, with those types.

## Guarantees

| Guarantee | Detail |
|---|---|
| Grain | One row per day from 2021-01-01 to 2030-12-31, plus two members |
| Key stability | A day's `sk_tempo` never changes; the table is never rebuilt by the script |
| Members | `-1` = unknown date, `-2` = not applicable; `data` is NULL on both |
| Key sign | Days have positive keys; only members are negative |
| Lookup | Resolve `sk_tempo` with `dim_tempo.data = CAST(<event timestamp> AS DATE)`; no match → `-1` |
| Names | `mes` and `dia_semana` in lowercase Portuguese |
| Weeks | `semana_ano` is the ISO week: early-January days can read week 52/53 and late-December days week 1 |

## Not guaranteed

- Keys are not consecutive and do not follow date order: do not sort or range-filter by
  `sk_tempo`; use `data`.
- Dates outside the period have no row.

## Producer

`explorations/setup/04_dim_tempo.sql` only. No pipeline dataset and no notebook writes to
this table.
