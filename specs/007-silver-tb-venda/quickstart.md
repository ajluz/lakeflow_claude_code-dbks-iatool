# Quickstart: Validate the Sales Table

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

Shapes are in [data-model.md](data-model.md) and
[contracts/silver-tb-venda.md](contracts/silver-tb-venda.md). Every CLI command takes
`--profile databricks-free`. `<pipeline_id>` is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.

## Prerequisites

- **Login**: the `databricks-free` login expired on 2026-10-28. The owner runs
  `databricks auth login --profile databricks-free` first.
- Features 004, 005 and 006 are deployed.
- `09_vw_silver_tb_venda_api.sql`, `10_vw_silver_tb_venda_files.sql` and
  `11_tb_venda.sql` exist under `src/pipeline/02_silver/`.
- **Free Edition**:
  - Stop the SQL warehouse (`databricks warehouses stop f796ffb64302b6ba`) and wait about
    4 minutes after the previous update before starting one.
  - Never stop the warehouse while queries are still running on it.
  - A serverless notebook left attached holds the quota.

## 1. Before the run: facts and expected counts

These settle the three facts research could not measure (Decisions 4, 6 and 7).

```sql
-- Installment field name: expect valor_parcelas inside info_pagamento
SELECT full_data_type FROM workspace.information_schema.columns
WHERE table_schema = 'bronze' AND table_name = 'dados_api' AND column_name = 'payload';

-- API sales: valid events with a payment
SELECT count(*)                                                     AS api_vendas,
       count_if(payload.info_pagamento.disconto IS NULL)            AS sem_desconto,
       count_if(ip_address = '999.999.999.999')                     AS acesso_descartado,
       count_if(payload.info_usuario.sexo IS NULL
                OR payload.info_usuario.sexo NOT IN ('M','F'))      AS usuario_descartado,
       count_if(CAST(try_cast(payload.info_pagamento.quantidade_parcelas AS INT)
                     * CAST(payload.info_pagamento.valor_parcelas AS DECIMAL(9,2)) AS DECIMAL(9,2))
                != CAST(payload.info_pagamento.valor AS DECIMAL(9,2))) AS parcelas_divergentes,
       count(*) - count(DISTINCT try_to_timestamp(access_date), ip_address,
             CASE WHEN lower(access_point) IN ('iphone', 'android') THEN 'Mobile'
                  WHEN lower(access_point) IN ('chrome', 'safari', 'firefox') THEN 'Computador'
                  ELSE 'unknown' END,
             payload.info_produto.product_name)                     AS chaves_venda_repetidas
FROM workspace.bronze.dados_api
WHERE (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
  AND (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00')
  AND (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----')
  AND payload.info_pagamento IS NOT NULL;

-- Files sales
SELECT count(*) AS arquivo_vendas,
       count(*) - count(DISTINCT nome_empresa, nome_funcionario, data_venda, curso) AS chaves_venda_repetidas
FROM workspace.bronze.dados_files;
```

Record every number in `tasks.md`. Then:
- if the payload shows `valor_parcela`, change the API view to that name (Decision 6);
- if `chaves_venda_repetidas` is above 0 for the API, add `payload.info_usuario.nome` to
  the API `venda_uuid` (Decision 4);
- `parcelas_divergentes` is reported to the owner, with no change (Decision 7).

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` | `02_silver/` lists exactly `01_` to `11_`, all `FILE` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile databricks-free` | `COMPLETED`; the two flow views and `tb_venda` are defined, with two append flows into `tb_venda` |
| Run | `databricks pipelines start-update <pipeline_id> --profile databricks-free` | `COMPLETED`, no failed flow; the existing tables write only new data |

## 3. Contents of `tb_venda`

```sql
SELECT origem,
       count(*)                                        AS linhas,
       count_if(venda_uuid IS NULL)                    AS sem_chave,
       count_if(acesso_uuid IS NOT NULL)               AS com_acesso,
       count_if(valor_pago IS NULL OR valor_pago <= 0) AS valor_invalido,
       count_if(valor_desconto IS NULL)                AS sem_valor_desconto,
       count_if(percentual_desconto NOT IN ('0%','5%','10%','15%')
                OR percentual_desconto IS NULL)        AS percentual_fora,
       count_if(origem = 'ARQUIVO' AND (forma_pagamento != 'pix' OR quantidade_parcelas != 1)) AS arquivo_fora,
       count_if(data_carga IS NULL)                    AS sem_data_carga
FROM workspace.silver.tb_venda GROUP BY origem ORDER BY origem;

SELECT count(*) - count(DISTINCT venda_uuid) AS chaves_repetidas FROM workspace.silver.tb_venda;

SELECT percentual_desconto, origem, count(*), min(valor_desconto), max(valor_desconto)
FROM workspace.silver.tb_venda GROUP BY ALL ORDER BY ALL;

SELECT concat_ws(', ', collect_list(column_name)) FROM (
  SELECT column_name FROM workspace.information_schema.columns
  WHERE table_schema = 'silver' AND table_name = 'tb_venda' ORDER BY ordinal_position);

-- Joins to access, user and course
SELECT
  count_if(v.origem = 'API' AND a.acesso_uuid IS NULL)  AS api_sem_acesso,
  count_if(u.usuario_uuid IS NULL)                      AS sem_usuario,
  count_if(v.curso_uuid NOT IN (md5('Construindo um Data Lakehouse com SQL e DLT'),
                                md5('Mastering SQL no Databricks'),
                                md5('Programa Data Heroes'))) AS curso_fora
FROM workspace.silver.tb_venda v
LEFT JOIN (SELECT DISTINCT acesso_uuid FROM workspace.silver.tb_acesso) a ON v.acesso_uuid = a.acesso_uuid
LEFT JOIN (SELECT DISTINCT usuario_uuid FROM workspace.silver.tb_usuario) u ON v.usuario_uuid = u.usuario_uuid;
```

Expected:
- `API`: `linhas` = `api_vendas` of step 1, `com_acesso` = `linhas`;
- `ARQUIVO`: `linhas` = `arquivo_vendas` of step 1, `com_acesso` = 0;
- `sem_chave`, `valor_invalido`, `sem_valor_desconto`, `percentual_fora`,
  `arquivo_fora`, `sem_data_carga`, `chaves_repetidas` and `curso_fora` are 0;
- discount amounts are those of the table in research, and `0.00` for `0%`;
- the columns are the 13 of the data model, in order;
- `SHOW TBLPROPERTIES workspace.silver.tb_venda ('quality')` is `silver`;
- `api_sem_acesso` = `acesso_descartado` of step 1, and `sem_usuario` =
  `usuario_descartado` of step 1. Record both.

## 4. Expectations, from the event log

Use feature 004's quickstart step 4 queries for the update of step 2. Expected for dataset
`tb_venda`, summed over both flows: `failed` = 0 for `check_venda_uuid`,
`check_usuario_uuid`, `check_curso_uuid`, `check_data_venda` and `check_valor_pago`, and
`passed` = `api_vendas` + `arquivo_vendas` for each.

Reconciliation, per source: sales candidates = rows in `tb_venda`, with no exclusion.

## 5. Incremental behavior

Run another update with no new landing data. Expected: both `tb_venda` flows write 0
rows, and the counts of step 3 are unchanged.
