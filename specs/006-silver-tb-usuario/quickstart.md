# Quickstart: Validate the User Table

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

Shapes are in [data-model.md](data-model.md) and
[contracts/silver-tb-usuario.md](contracts/silver-tb-usuario.md). Every CLI command takes
`--profile databricks-free`. `<pipeline_id>` is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.

## Prerequisites

- Features 004 and 005 are deployed.
- `02_vw_bronze_dados_files.sql`, `06_vw_silver_tb_usuario_api.sql`, `07_vw_silver_tb_usuario_files.sql` and `08_tb_usuario.sql` exist under `src/pipeline/02_silver/` (revised for constitution v1.9.0).
- **Free Edition**:
  - Stop the SQL warehouse (`databricks warehouses stop f796ffb64302b6ba`) and wait about 4 minutes after the previous update before starting one.
  - Never stop the warehouse while queries are still running on it.
  - A serverless notebook left attached holds the quota.

## 1. Before the run: expected counts

```sql
-- API candidates (valid events with a user)
SELECT count(*) AS api_candidatos,
       count_if(payload.info_usuario.sexo IN ('M','F')) AS api_mantidos,
       count_if(NOT (payload.info_usuario.sexo IN ('M','F')) OR payload.info_usuario.sexo IS NULL) AS api_sexo_invalido,
       count_if(payload.info_usuario.email IS NULL OR NOT payload.info_usuario.email LIKE '%@%') AS api_email_invalido
FROM workspace.bronze.dados_api
WHERE (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
  AND (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00')
  AND (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----')
  AND payload.info_usuario.nome IS NOT NULL;

-- Files candidates
SELECT count(DISTINCT nome_empresa, nome_funcionario) AS arquivo_chaves,
       count_if(sexo IN ('M','F')) AS arquivo_sexo_ok,
       count_if(email_funcionario IS NULL OR NOT email_funcionario LIKE '%@%') AS arquivo_email_invalido
FROM workspace.bronze.dados_files;
```

Expected on 2026-10-18:
- API: 756,249 candidates, 741,234 kept, 15,015 with invalid sex, 30,190 with an invalid email;
- files: 200,000 keys, 200,000 with valid sex, 0 with an invalid email.

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` | `02_silver/` lists exactly `01_` to `08_`, all `FILE` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile databricks-free` | `COMPLETED`; `vw_bronze_dados_files`, the two flow views and `tb_usuario` are defined, with two append flows into `tb_usuario` |
| Run | `databricks pipelines start-update <pipeline_id> --profile databricks-free` | `COMPLETED`, no failed flow |

## 3. Contents of `tb_usuario`

```sql
SELECT origem,
       count(*)                                   AS linhas,
       count_if(sexo_usuario NOT IN ('M','F') OR sexo_usuario IS NULL) AS sexo_invalido,
       count_if(usuario_uuid IS NULL)             AS sem_chave,
       count_if(empresa_usuario IS NOT NULL)      AS com_empresa,
       count_if(data_carga IS NULL)               AS sem_data_carga,
       count_if(idade_usuario IS NULL)            AS sem_idade
FROM workspace.silver.tb_usuario GROUP BY origem ORDER BY origem;

SELECT count(*) - count(DISTINCT usuario_uuid) AS chaves_repetidas FROM workspace.silver.tb_usuario;

SELECT concat_ws(', ', collect_list(column_name)) FROM (
  SELECT column_name FROM workspace.information_schema.columns
  WHERE table_schema = 'silver' AND table_name = 'tb_usuario' ORDER BY ordinal_position);

-- API users join their accesses
SELECT count(*) AS api_sem_acesso
FROM workspace.silver.tb_usuario u
LEFT ANTI JOIN (SELECT DISTINCT usuario_uuid FROM workspace.silver.tb_acesso WHERE usuario_uuid IS NOT NULL) a
  ON u.usuario_uuid = a.usuario_uuid
WHERE u.origem = 'API';

-- Files key recomputes
SELECT count(*) AS chave_arquivo_divergente
FROM workspace.silver.tb_usuario u
LEFT ANTI JOIN (SELECT md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''))) AS k
                FROM workspace.bronze.dados_files) f ON u.usuario_uuid = f.k
WHERE u.origem = 'ARQUIVO';
```

Expected:
- `API`: `linhas` = 741,234, `com_empresa` = 0;
- `ARQUIVO`: `linhas` = 200,000, `com_empresa` = 200,000;
- `sexo_invalido`, `sem_chave` and `sem_data_carga` are 0 for both;
- `chaves_repetidas`, `chave_arquivo_divergente` and `api_sem_acesso` are 0;
- the columns are the 10 of the data model, in order;
- `SHOW TBLPROPERTIES workspace.silver.tb_usuario ('quality')` is `silver`.

`api_sem_acesso` can be above 0 only for users whose access was dropped by
`tb_acesso`'s address rule. That would be expected; record the number.

## 4. Expectations, from the event log

Use feature 004's quickstart step 4 queries for the update of step 2. Expected for dataset
`tb_usuario`, summed over both flows:

| Expectation | failed |
|---|---|
| `check_sexo_usuario` | 15,015 |
| `check_email_usuario` | 30,190 |
| `check_usuario_uuid` | 0 |

`passed` + `failed` = 956,249 (756,249 + 200,000) for each rule. Reconciliation:
candidates = rows in `tb_usuario` + failed of `check_sexo_usuario`. If
`chaves_repetidas` (step 3) is ever above 0, report it to the owner: the table appends
and does not merge.

## 5. Incremental behavior

Run another update with no new landing data. Expected: both `tb_usuario` flows write 0
rows, and the counts of step 3 are unchanged.
