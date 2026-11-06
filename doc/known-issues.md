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

## Smaller items

- `obt_acesso` is still the earlier pipeline's
  [05_obt_acesso.sql](../code_tips/03_gold/05_obt_acesso.sql), whose access-row join is still
  to be rebuilt. `fato_venda` (feature 013) no longer drops sales: every lookup is a
  `LEFT JOIN` that falls back to the unknown member `-1`.
- [05_tb_acesso.sql:1](../code_tips/02_silver/05_tb_acesso.sql#L1) uses
  `CREATE OR REPLACE` where every other table uses `CREATE OR REFRESH`.
- `dim_curso` and `tb_curso` both read the bronze change feed, through
  `vw_bronze_tb_curso`. This is by design (constitution Principle I): `tb_curso` is SCD
  type 1 and keeps no history, so `dim_curso` (SCD type 2) cannot read it. `tb_curso` is
  the silver reference that sales and accesses join on `curso_uuid`.
- `AUTO CDC ... FROM SNAPSHOT` cannot share a target with change flows when the target is SCD
  type 2 (`MULTI_QUERY_SNAPSHOT_TARGET_NOT_SUPPORTED`, feature 012); the Databricks CDC page
  limits that pattern to SCD type 1. `dim_usuario` (type 1) loads its members that way;
  `dim_curso` (type 2) loads them with an `AUTO CDC ONCE` flow from a view instead. No identity
  key remains in gold: `dim_usuario`, `dim_codigos` and `dim_curso` use `xxhash64` keys.
- `dim_usuario` declares no expectations (feature 009, by the owner's decision), so a null key
  would not stop an update.
- The bronze filter in [user_case.py](../explorations/user_case.py) mixes
  `AND` and `OR` without parentheses, so `WHERE 1=1 AND a OR b OR c` does not
  group the way the comments suggest once more conditions are uncommented.
- [clean_up_env.ipynb](../explorations/clean_up_env.ipynb) nests single quotes
  inside a single-quoted f-string (`f'DROP TABLE {row['tableName']}'`), which
  needs Python 3.12 or later.
