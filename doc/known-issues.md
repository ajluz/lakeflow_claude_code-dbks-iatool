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

## File sales get a wrong paid amount

In [08_vw_silver_tb_venda_files.sql:13-14](../code_tips/02_silver/08_vw_silver_tb_venda_files.sql#L13-L14),
the discount subtracted from the price is computed with `replace(..., ',', '')`
where the rest of the file uses `replace(..., ',', '.')`. `R$ 247,00` becomes
`24700` instead of `247.00`, so the discount is 100 times too large and
`valor_parcelas` and `valor_pago` come out negative (247.00 − 1235.00 for a 5%
discount). `valor_desconto` on line 16 is correct.

## Sales missing from fato_venda

[04_fato_vendas.sql](../code_tips/03_gold/04_fato_vendas.sql) uses inner joins
throughout, which drops three groups of sales:

- **All file sales.** They have a null `acesso_uuid`
  ([08_vw_silver_tb_venda_files.sql:5](../code_tips/02_silver/08_vw_silver_tb_venda_files.sql#L5))
  and cannot match `tb_acesso`. The `CASE WHEN v.origem = 'ARQUIVO'` branch on
  line 8 is therefore never reached.
- **Sales without a discount.** `percentual_disconto` is null for them in
  `tb_venda`. `dim_codigos` stores `'Não se aplica'` for that case, but the fact
  query compares the raw null, which never matches. With about 70% of API
  payments undiscounted, most sales are affected.
- **Sales whose access row was dropped or keyed differently.** `tb_acesso`
  drops rows with the `999.999.999.999` address, and the two files derive
  `acesso_uuid` differently: [05_tb_acesso.sql:22-30](../code_tips/02_silver/05_tb_acesso.sql#L22-L30)
  hashes `Mobile` / `Computador` / `unknown`, while
  [07_vw_silver_tb_venda_api.sql:5-9](../code_tips/02_silver/07_vw_silver_tb_venda_api.sql#L5-L9)
  hashes only `Mobile` / `Computador`. Events with an `unknown` access point get
  two different keys.

The same key mismatch affects the left join in
[05_obt_acesso.sql](../code_tips/03_gold/05_obt_acesso.sql), undercounting
`qtde_vendidos`.

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
- `dim_curso` and `tb_curso` both read the bronze change feed. `tb_curso` is not
  consumed by any gold table.
- Identity surrogate keys are declared on materialized views (`dim_usuario`,
  `dim_codigos`) and on an `AUTO CDC` target (`dim_curso`). Databricks documents
  that identity values on materialized views can be recomputed when the view is
  refreshed, which would change keys under `fato_venda`; worth confirming
  against the current documentation.
- The bronze filter in [user_case.py](../explorations/user_case.py) mixes
  `AND` and `OR` without parentheses, so `WHERE 1=1 AND a OR b OR c` does not
  group the way the comments suggest once more conditions are uncommented.
- [clean_up_env.ipynb](../explorations/clean_up_env.ipynb) nests single quotes
  inside a single-quoted f-string (`f'DROP TABLE {row['tableName']}'`), which
  needs Python 3.12 or later.
