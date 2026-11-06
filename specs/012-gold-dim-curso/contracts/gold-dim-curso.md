# Contract: `workspace.gold.dim_curso`

What consumers (`fato_venda`, Genie, dashboards) may rely on.

## Schema

The 8 columns of [data-model.md](../data-model.md), in that order, with those types.

## Guarantees

| Guarantee | Detail |
|---|---|
| Grain | One row per version of a course, plus two members |
| History | A change never overwrites or removes a version. An update closes the open version and opens a new one; a delete closes the open version |
| Validity | A version is valid on `[__START_AT, __END_AT)`, in the catalog's change time. `__END_AT IS NULL` means current |
| Current = silver | The current course rows hold the same courses, names, levels and prices as `silver.tb_curso` |
| Key per version | Each version has its own `sk_curso`. It never changes across updates, full refreshes or later changes of the course |
| Key sign | Course versions positive; `-1` = unknown, `-2` = not applicable |
| Members | Always current, valid from `1900-01-01` |
| Lookup | A fact resolves the version where `curso_uuid` matches and the fact's time is in `[__START_AT, __END_AT)` (`__END_AT` open counts as infinite). No match → `-1` |

## Not guaranteed

- That a version reflects a real change of values: the source can send an update that
  repeats them (research, Decision 4).
- The order of two changes of one course with the same change time.
- `data_carga` is when gold wrote the version, not when it was closed.

## Producer

`src/pipeline/03_gold/04_vw_gold_dim_curso_dados_database.sql` and
`src/pipeline/03_gold/05_dim_curso.sql`, pipeline `lakeflow_dataslight_dev`. Reads bronze
through `vw_bronze_tb_curso` (constitution, Principle I exception).
