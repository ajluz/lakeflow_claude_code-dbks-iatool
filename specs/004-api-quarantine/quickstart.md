# Quickstart: Validate the API Quarantine

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

How to prove the feature works end to end. Table shapes are in
[data-model.md](data-model.md); the definitions' shape is in
[contracts/silver-validation-quarantine.md](contracts/silver-validation-quarantine.md).

Every CLI command takes `--profile <profile>`. The owner chooses the profile; it is never
picked for them. `<pipeline_id>` is the id of `lakeflow_dataslight_dev` (feature 003).

## Prerequisites

- Features 001–003 are in place: the schemas, the landing volume, and a pipeline whose
  latest update completed with `workspace.bronze.dados_api` populated.
- The two files of this feature exist under `src/pipeline/02_silver/`.
- Queries run on a SQL warehouse or in the SQL editor of the same workspace.

## 1. Before the run: expected counts from bronze

Read the type of the payment value (research, Decision 4):

```sql
DESCRIBE TABLE workspace.bronze.dados_api;   -- note the type of payload.info_pagamento.valor
```

Count what each rule should reject. The conditions are those of
[data-model.md](data-model.md#validation-rules), negated:

```sql
SELECT
  count(*) AS total,
  count_if(NOT (payload.info_produto.product_name IS NULL
                OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')) AS curso_invalido,
  count_if(NOT (payload.info_pagamento.valor IS NULL
                OR payload.info_pagamento.valor != '0.00'))                                  AS valor_invalido,
  count_if(NOT (payload.info_pagamento.forma_pagamento IS NULL
                OR payload.info_pagamento.forma_pagamento != '-----'))                       AS forma_pagamento_invalido,
  count_if(_rescued_data IS NOT NULL)                                                        AS registro_nao_conforme,
  count_if(NOT (
        (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
    AND (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00')
    AND (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----')
    AND _rescued_data IS NULL))                                                              AS invalidos
FROM workspace.bronze.dados_api;
```

Expected: `curso_invalido`, `valor_invalido` and `forma_pagamento_invalido` are each
greater than 0, because the generator produces all three placeholders.
`registro_nao_conforme` is 0 today. If `valor_invalido` is 0, stop and report it to the
owner (research, Decision 4). Keep these numbers for steps 3 and 4.

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile <profile>` | `02_silver/` appears in the workspace |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile <profile>` | update `COMPLETED`; the graph shows `dados_api → temp_tb_validacao_api → tb_quarentena` |
| Run | `databricks pipelines start-update <pipeline_id> --profile <profile>` | returns an `update_id` |
| Wait | `databricks pipelines get-update <pipeline_id> <update_id> --profile <profile>` | `.update.state` = `COMPLETED`, no failed flow |

Never pass `--full-refresh`. If the dry run rejects the three-level private name or
`CLUSTER BY` on the private table, stop and report it. Do not switch to `PARTITIONED BY` or
drop the qualifier (research, Decision 2).

## 3. Quarantine contents

```sql
-- Counts: total quarantined, and per rule
SELECT count(*) AS quarentena FROM workspace.silver.tb_quarentena;

SELECT regra, count(*) AS linhas
FROM workspace.silver.tb_quarentena
LATERAL VIEW explode(regras_violadas) AS regra
GROUP BY regra
ORDER BY regra;

-- Lineage, record source and reasons are always populated
SELECT
  count_if(origem IS DISTINCT FROM 'API') AS origem_errada,
  count_if(data_carga IS NULL)            AS sem_data_carga,
  count_if(size(regras_violadas) = 0)     AS sem_regra
FROM workspace.silver.tb_quarentena;

-- Quarantine equals the invalid bronze rows, field for field, in both directions
WITH bronze_invalido AS (
  SELECT * FROM workspace.bronze.dados_api
  WHERE NOT (
        (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
    AND (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00')
    AND (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----')
    AND _rescued_data IS NULL)
),
quarentena AS (
  SELECT * EXCEPT (regras_violadas, origem, data_carga) FROM workspace.silver.tb_quarentena
)
SELECT 'só na quarentena' AS lado, count(*) AS linhas FROM (SELECT * FROM quarentena EXCEPT ALL SELECT * FROM bronze_invalido)
UNION ALL
SELECT 'só no bronze', count(*) FROM (SELECT * FROM bronze_invalido EXCEPT ALL SELECT * FROM quarentena);
```

Expected: `quarentena` equals `invalidos` from step 1. Each per-rule count equals the same
rule's count from step 1. The three checks are 0. Both `EXCEPT ALL` sides are 0.

## 4. Validation table and expectations, from the event log

The validation table is private, so its numbers come from the event log.

```sql
-- Rows written by each flow in the latest update
SELECT origin.flow_name,
       sum(CAST(details:flow_progress.metrics.num_output_rows AS BIGINT)) AS linhas
FROM event_log('<pipeline_id>')
WHERE event_type = 'flow_progress'
  AND origin.update_id = '<update_id>'
GROUP BY origin.flow_name;

-- Pass and fail counts per expectation in the latest update
SELECT e.dataset, e.name,
       sum(e.passed_records) AS passou,
       sum(e.failed_records) AS falhou
FROM (
  SELECT explode(from_json(details:flow_progress.data_quality.expectations,
         'array<struct<name:string,dataset:string,passed_records:bigint,failed_records:bigint>>')) AS e
  FROM event_log('<pipeline_id>')
  WHERE event_type = 'flow_progress'
    AND origin.update_id = '<update_id>'
) GROUP BY e.dataset, e.name
ORDER BY e.dataset, e.name;
```

Expected:

- The validation flow wrote `total` rows (step 1): nothing was dropped (SC-001).
- The quarantine flow wrote `invalidos` rows.
- `temp_tb_validacao_api` lists the four rules (SC-003). Each rule's `falhou` equals its
  count from step 1 and its count in step 3. A difference means the `CONSTRAINT` text and
  the `regras_violadas` line of that rule drifted apart.
- `tb_quarentena` lists `regra_violada_registrada` with `falhou` = 0.
- In the pipeline UI, the data quality tab of both tables shows these expectations.

Reconciliation (SC-004): valid = `total` − `invalidos`; bronze = valid + quarantined, with a
difference of 0.

## 5. Incremental behavior

Run the pipeline again (step 2, "Run" and "Wait") without adding files.

Expected: both flows write 0 rows in the new update, and the quarantine count from step 3
is unchanged (SC-007).

Optional, to see new data flow through: generate one new batch of API events with the
project's generator, run again, repeat steps 1 and 3, and confirm both tables grew by the
new events only.

## 6. Definitions

Read the two files against the contract:

- the validation statement is `PRIVATE`, has `CLUSTER BY (fl_registro_invalido)` and no
  `PARTITIONED BY` (spec, User Story 1 scenario 8). A private table cannot be inspected
  with `DESCRIBE DETAIL`, so the definition and a successful dry run are the evidence;
- the four `CONSTRAINT` conditions and the four `CASE` lines are identical, rule by rule;
- no `ON VIOLATION` appears in either file.
