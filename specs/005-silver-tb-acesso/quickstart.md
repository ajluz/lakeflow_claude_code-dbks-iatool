# Quickstart: Validate the Access Table

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

How to prove the feature works end to end. Shapes are in [data-model.md](data-model.md)
and [contracts/silver-tb-acesso.md](contracts/silver-tb-acesso.md).

Every CLI command takes `--profile databricks-free` (the owner's choice). `<pipeline_id>`
is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.

## Prerequisites

- Feature 004 is deployed: `temp_tb_validacao_api` and `tb_quarentena` exist and are
  filled.
- The two files of this feature exist under `src/pipeline/02_silver/`.
- **Free Edition**: queries wake the SQL warehouse, which shares the serverless quota with
  the pipeline. Stop the warehouse (`databricks warehouses stop f796ffb64302b6ba`) and
  wait about 4 minutes after the previous update before starting one.

## 1. Before the run: expected counts

The valid events, as `tb_acesso` will see them:

```sql
WITH v AS (
  SELECT ip_address,
         CASE WHEN lower(access_point) IN ('iphone','android') THEN 'Mobile'
              WHEN lower(access_point) IN ('chrome','safari','firefox') THEN 'Computador'
              ELSE 'unknown' END AS local_acesso,
         try_to_timestamp(access_date) AS ts
  FROM workspace.bronze.dados_api
  WHERE (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
    AND (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00')
    AND (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----')
)
SELECT count(*)                                                              AS validos,
       count_if(ip_address = '999.999.999.999')                              AS ip_invalido,
       count_if(ip_address IS NULL OR ip_address != '999.999.999.999')       AS mantidos,
       count_if(local_acesso = 'unknown' AND (ip_address IS NULL OR ip_address != '999.999.999.999')) AS unknown_mantidos,
       count_if(ts IS NULL)                                                  AS sem_timestamp
FROM v;
```

Expected on 2026-10-18: `validos` 2,541,715; `ip_invalido` 25,523; `mantidos` 2,516,192;
`sem_timestamp` 0. Keep the numbers for the next steps.

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` | `04_vw_silver_eventos_api.sql` and `05_tb_acesso.sql` appear in `02_silver/` as `FILE` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile databricks-free` | `COMPLETED`; the events define `vw_silver_eventos_api` and `tb_acesso` |
| Run | `databricks pipelines start-update <pipeline_id> --profile databricks-free` | `COMPLETED`, no failed flow |

No refresh is needed: both datasets are new.

## 3. Contents of `tb_acesso`

```sql
-- Row count and rule outcomes
SELECT count(*)                                         AS linhas,
       count_if(endereco_ip_acesso = '999.999.999.999') AS ip_invalido,
       count_if(local_acesso = 'unknown')               AS unknown,
       count_if(local_acesso NOT IN ('Mobile','Computador','unknown')) AS categoria_errada,
       count_if(timestamp_acesso IS NULL)               AS sem_timestamp,
       count_if(acesso_uuid IS NULL)                    AS sem_chave,
       count(*) - count(DISTINCT acesso_uuid)           AS chaves_repetidas,
       count_if(origem IS DISTINCT FROM 'API')          AS origem_errada,
       count_if(data_carga IS NULL)                     AS sem_data_carga
FROM workspace.silver.tb_acesso;

-- Exactly the 8 columns, in order
SELECT concat_ws(', ', collect_list(column_name)) FROM (
  SELECT column_name FROM workspace.information_schema.columns
  WHERE table_schema = 'silver' AND table_name = 'tb_acesso' ORDER BY ordinal_position);

-- Keys recompute from their fields
SELECT count_if(acesso_uuid != md5(concat_ws('||', coalesce(cast(timestamp_acesso AS STRING), ''),
                coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, '')))) AS acesso_uuid_divergente
FROM workspace.silver.tb_acesso;

-- Every course reference joins the catalog
SELECT count_if(curso_uuid IS NOT NULL)                  AS com_curso,
       count_if(curso_uuid IS NOT NULL AND c.curso_uuid IS NULL) AS sem_catalogo
FROM workspace.silver.tb_acesso a
LEFT JOIN (SELECT DISTINCT curso_uuid FROM workspace.bronze.dados_database) c USING (curso_uuid);
```

Expected:
- `linhas` = `mantidos`, and `unknown` = `unknown_mantidos`;
- `ip_invalido`, `categoria_errada`, `sem_timestamp`, `sem_chave`, `chaves_repetidas`, `origem_errada`, `sem_data_carga`, `acesso_uuid_divergente` and `sem_catalogo` are all 0;
- the column list is `timestamp_acesso, endereco_ip_acesso, local_acesso, acesso_uuid, usuario_uuid, curso_uuid, origem, data_carga`;
- `SHOW TBLPROPERTIES workspace.silver.tb_acesso ('quality')` is `silver`.

## 4. Expectations and reconciliation, from the event log

Use the queries of feature 004's quickstart step 4, for the update of step 2.

Expected for dataset `tb_acesso`:

Every expectation is evaluated on every row of the query, including rows that
`check_endereco_ip_acesso` then drops. So passed + failed = `validos` for each rule
(confirmed on 2026-10-18):

| Expectation | failed | passed |
|---|---|---|
| `check_endereco_ip_acesso` | `ip_invalido` (25,523) | `mantidos` |
| `check_local_acesso` | all valid `unknown` events (118,305), dropped ones included; the table keeps `unknown_mantidos` (117,131) | `validos` − failed |
| `check_timestamp_acesso` | 0 | `validos` |
| `check_acesso_uuid` | 0 | `validos` |

The `tb_acesso` flow wrote `mantidos` rows. Reconciliation: `validos` = rows in
`tb_acesso` + failed of `check_endereco_ip_acesso`, with a difference of 0.

## 5. Incremental behavior

Run another update with no new landing data. Expected: the `tb_acesso` flow writes 0
rows, and the count of step 3 is unchanged.

## 6. Definitions

- `05_tb_acesso.sql` has the active `check_local_acesso` warn line, followed by the
  commented `FAIL UPDATE` line.
- Neither file computes `uuid()`, `rand()` or a load time inside a key.
- `usuario_uuid` and `curso_uuid` are computed only in `04_vw_silver_eventos_api.sql`; `05_tb_acesso.sql` only selects them.
