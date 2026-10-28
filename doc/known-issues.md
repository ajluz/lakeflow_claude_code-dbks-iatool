# Known issues

Found by reading the code while writing this documentation. Nothing here was
run against a workspace, so each item is a reading of the source, not an
observed failure. None of the code has been changed.

## Catalog name mismatch

The pipeline targets the `workspace` catalog, but a few places still reference
`dataslight_dev`:

| Location | Reference |
|---|---|
| [user_case.py](../explorations/user_case.py), last two queries | `dataslight_dev.gold.*` |
| [clean_up_env.ipynb](../explorations/clean_up_env.ipynb) | `USE dataslight_dev.*` and `/Volumes/dataslight_dev/...` |

## Sales missing from fato_venda

[04_fato_vendas.sql](../code_tips/03_gold/04_fato_vendas.sql), from the earlier pipeline,
uses inner joins throughout. Against the new `silver.tb_venda` (feature 007) it would
still drop two groups of sales:

- **All file sales.** They have a null `acesso_uuid` and cannot match `tb_acesso`. The
  `CASE WHEN v.origem = 'ARQUIVO'` branch on line 8 is therefore never reached.
- **Sales whose access or user row was dropped.** `tb_acesso` drops events with the
  `999.999.999.999` address (2,174 sales on 2026-10-28), and `tb_usuario` drops users
  whose sex is not `M` or `F` (4,362 sales).

The same applies to the left join in
[05_obt_acesso.sql](../code_tips/03_gold/05_obt_acesso.sql) for the access rows. The gold
rebuild resolves these lookups to an explicit "unknown" member (Principle VII).

Fixed in silver by feature 007 (2026-10-28):
- the paid amount of file sales: the price is now parsed as `247.00`, not `24700`, so no
  amount is negative;
- the empty discount: sales without a discount carry `0%` and `0.00`;
- the `acesso_uuid` mismatch for `unknown` access points: `tb_venda` uses `tb_acesso`'s
  expression.

## dim_tempo is reloaded on every run

The last cell of [functions.py](../explorations/functions.py#L514) creates
`dim_tempo` with `IF NOT EXISTS` but then inserts unconditionally. Every
`%run "./functions"` appends another full copy of the calendar. Since
`fato_venda` and `obt_acesso` join on `data`, each extra copy multiplies their
rows.

## dim_codigos is built from a cross join

[03_dim_codigos.sql:17-18](../code_tips/03_gold/03_dim_codigos.sql#L17-L18)
cross joins `tb_venda` with `tb_acesso` before `DISTINCT`. The result is
correct, but the intermediate row count is the product of both tables, which is
expensive at the volumes the generators produce.

## Smaller items

- [05_tb_acesso.sql:1](../code_tips/02_silver/05_tb_acesso.sql#L1) uses
  `CREATE OR REPLACE` where every other table uses `CREATE OR REFRESH`.
- `dim_curso` and `tb_curso` both read the bronze change feed, through
  `vw_bronze_tb_curso`. This is by design (constitution Principle I): `tb_curso` is SCD
  type 1 and keeps no history, so `dim_curso` (SCD type 2) cannot read it. `tb_curso` is
  the silver reference that sales and accesses join on `curso_uuid`.
- Identity surrogate keys are declared on a materialized view (`dim_codigos`) and on an
  `AUTO CDC` target (`dim_curso`) in the earlier pipeline. Identity columns are not
  supported on materialized views (`databricks-pipelines` skill), and keys that can be
  reassigned would change under `fato_venda`. `dim_usuario` no longer has this issue: since
  feature 009 its key is `xxhash64(usuario_uuid)`, which never changes for a user.
- The bronze filter in [user_case.py](../explorations/user_case.py) mixes
  `AND` and `OR` without parentheses, so `WHERE 1=1 AND a OR b OR c` does not
  group the way the comments suggest once more conditions are uncommented.
- [clean_up_env.ipynb](../explorations/clean_up_env.ipynb) nests single quotes
  inside a single-quoted f-string (`f'DROP TABLE {row['tableName']}'`), which
  needs Python 3.12 or later.
