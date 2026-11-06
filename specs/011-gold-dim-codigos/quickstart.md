# Quickstart: Gold Junk Dimension of Sale Codes

Validates the feature end to end. Expected values from [spec.md](spec.md) and
[data-model.md](data-model.md), as of 2026-11-05.

## Prerequisites

- Profile `databricks-free`, logged in; pipeline `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`
  idle; warehouse `f796ffb64302b6ba`.
- `src/pipeline/03_gold/03_dim_codigos.sql` uploaded to the pipeline's workspace folder.
- About 4 minutes between pipeline updates (Free Edition quota).

## 1. Dry run, then update

```bash
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --validate-only --profile databricks-free
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free
```

Expected: both `COMPLETED`; `dim_codigos` is created as a `MATERIALIZED_VIEW`; no other
dataset fails. Not a full refresh.

## 2. Content

```sql
SELECT
  count(*)                                                       AS linhas,          -- 62
  count(DISTINCT sk_codigos)                                     AS chaves,          -- 62
  count(DISTINCT origem_usuario, local_acesso, forma_pagamento, percentual_desconto) AS combinacoes, -- 62
  count_if(sk_codigos IS NULL OR origem_usuario IS NULL OR local_acesso IS NULL
           OR forma_pagamento IS NULL OR percentual_desconto IS NULL) AS vazios,     -- 0
  count_if(sk_codigos < 0)                                       AS membros,         -- 2
  count_if(sk_codigos = 0)                                       AS chave_zero,      -- 0
  count_if(origem_usuario = 'ARQUIVO' AND local_acesso <> 'Não se aplica') AS arquivo_errado, -- 0
  count_if(origem_usuario = 'API' AND local_acesso = 'Não se aplica')      AS api_errado,     -- 0
  count_if(origem_usuario = 'API')                               AS api,             -- 48
  count_if(origem_usuario = 'ARQUIVO')                           AS arquivo,         -- 12
  count_if(local_acesso = 'Desconhecido' AND sk_codigos > 0)     AS sem_acesso       -- 12
FROM workspace.gold.dim_codigos;

SELECT * FROM workspace.gold.dim_codigos WHERE sk_codigos < 0 ORDER BY sk_codigos DESC;
-- -1 Desconhecido ×4, -2 Não se aplica ×4
```

Rows equal the product of the value lists (the cross join covers every possibility):

```sql
SELECT
  (SELECT count(DISTINCT local_acesso) + 1 FROM workspace.silver.tb_acesso)            -- 4
  * (SELECT count(DISTINCT coalesce(forma_pagamento, 'Desconhecido')) FROM workspace.silver.tb_venda)      -- 3
  * (SELECT count(DISTINCT coalesce(percentual_desconto, 'Não se aplica')) FROM workspace.silver.tb_venda) -- 4
  AS esperado_api,                                                                       -- 48
  (SELECT count(DISTINCT coalesce(forma_pagamento, 'Desconhecido')) FROM workspace.silver.tb_venda)
  * (SELECT count(DISTINCT coalesce(percentual_desconto, 'Não se aplica')) FROM workspace.silver.tb_venda)
  AS esperado_arquivo;                                                                   -- 12
```

(`+ 1` is `Desconhecido`; if silver ever produced that value itself the count would be one
less, which the `api` check above would show.)

## 3. Every sale matches one row (SC-003)

```sql
WITH vendas AS (
  SELECT v.origem AS origem_usuario,
         CASE WHEN v.origem = 'ARQUIVO' THEN 'Não se aplica'
              ELSE coalesce(a.local_acesso, 'Desconhecido') END AS local_acesso,
         coalesce(v.forma_pagamento, 'Desconhecido') AS forma_pagamento,
         coalesce(v.percentual_desconto, 'Não se aplica') AS percentual_desconto
  FROM workspace.silver.tb_venda AS v
  LEFT JOIN workspace.silver.tb_acesso AS a ON a.acesso_uuid = v.acesso_uuid
)
SELECT count(*) AS vendas,                                   -- 420472
       count_if(d.sk_codigos IS NULL) AS sem_linha,          -- 0
       count(DISTINCT d.sk_codigos) AS combinacoes_usadas    -- 22
FROM vendas AS s
LEFT JOIN workspace.gold.dim_codigos AS d
  USING (origem_usuario, local_acesso, forma_pagamento, percentual_desconto);
```

## 4. Keys survive a recompute (SC-004)

Record:

```sql
SELECT count(*) AS linhas,
       sum(hash(sk_codigos, origem_usuario, local_acesso, forma_pagamento, percentual_desconto)) AS checksum
FROM workspace.gold.dim_codigos;
```

Wait about 4 minutes, run a second ordinary update (step 1, second command), and repeat:
`linhas` and `checksum` identical; `max(data_carga)` moved to the new update. In the
event log of that update, the `planning_information` event for `dim_codigos` shows a
complete recompute, which is what makes this equivalent to a full refresh.

## 5. Nothing else changed

Bronze and silver row counts are unchanged by both updates; `dim_usuario` still has
941,236 rows.

Stop the warehouse afterwards with `--no-wait`.
