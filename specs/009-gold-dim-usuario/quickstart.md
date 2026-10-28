# Quickstart: Validate the User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

Shapes are in [data-model.md](data-model.md) and
[contracts/gold-dim-usuario.md](contracts/gold-dim-usuario.md). Every CLI command takes
`--profile databricks-free`. `<pipeline_id>` is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.

## Prerequisites

- `src/pipeline/03_gold/01_dim_usuario.sql` exists.
- Do not run the generators: the course demo must reach the talk in its initial state
  (feature 008).
- **Free Edition**: stop the SQL warehouse (`databricks warehouses stop f796ffb64302b6ba`)
  only when no query is running, and wait about 4 minutes after the previous update.

## 1. Before the run

```sql
SELECT count(*) AS usuarios, count(DISTINCT usuario_uuid) AS chaves,
       count(DISTINCT xxhash64(usuario_uuid)) AS sk_distintas
FROM workspace.silver.tb_usuario;
```

Expected on 2026-10-28: 941,234, 941,234, 941,234 (no hash collision).

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` | `03_gold/` lists `01_dim_usuario.sql` as `FILE` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile databricks-free` | `COMPLETED`; `workspace.gold.dim_usuario` defined |
| Run | `databricks pipelines start-update <pipeline_id> --profile databricks-free` | `COMPLETED`, no failed flow |

## 3. Contents of `dim_usuario`

```sql
SELECT count(*) AS linhas,
       count(DISTINCT sk_usuario) AS sk, count(DISTINCT usuario_uuid) AS bk,
       count_if(sk_usuario IS NULL OR usuario_uuid IS NULL) AS chave_vazia,
       count_if(sk_usuario IN (-1, -2)) AS membros,
       count_if(origem = 'API') AS api, count_if(origem = 'ARQUIVO') AS arquivo
FROM workspace.gold.dim_usuario;

SELECT * FROM workspace.gold.dim_usuario WHERE sk_usuario < 0 ORDER BY sk_usuario DESC;

-- Attributes equal silver's
SELECT count(*) AS divergentes
FROM workspace.silver.tb_usuario s
JOIN workspace.gold.dim_usuario d USING (usuario_uuid)
WHERE NOT (s.nome_usuario <=> d.nome_usuario AND s.email_usuario <=> d.email_usuario
       AND s.idade_usuario <=> d.idade_usuario AND s.sexo_usuario <=> d.sexo_usuario
       AND s.estado_usuario <=> d.estado_usuario AND s.profissao_usuario <=> d.profissao_usuario
       AND s.empresa_usuario <=> d.empresa_usuario AND s.origem <=> d.origem
       AND d.sk_usuario = xxhash64(s.usuario_uuid));

-- Users of sales without a dimension row (resolve to -1 in the fact)
SELECT count(DISTINCT v.usuario_uuid) AS sem_dimensao
FROM workspace.silver.tb_venda v
LEFT ANTI JOIN workspace.gold.dim_usuario d ON v.usuario_uuid = d.usuario_uuid;

SELECT concat_ws(', ', collect_list(concat(column_name, ' ', full_data_type))) FROM (
  SELECT column_name, full_data_type FROM workspace.information_schema.columns
  WHERE table_schema = 'gold' AND table_name = 'dim_usuario' ORDER BY ordinal_position);
```

Expected:
- `linhas` = `sk` = `bk` = 941,236; `chave_vazia` 0; `membros` 2; `api` 741,234;
  `arquivo` 200,000;
- the two members as in the data model;
- `divergentes` 0;
- `sem_dimensao` 4,362;
- the 11 columns of the data model, in order, `sk_usuario bigint`;
- `SHOW TBLPROPERTIES workspace.gold.dim_usuario ('quality')` is `gold`.

## 4. Expectations

Feature 004's quickstart step 4 queries, for the update of step 2: `check_sk_usuario` and
`check_usuario_uuid` each failed 0, passed 941,236.

## 5. Key stability

Before the second update, save a sample:

```sql
SELECT usuario_uuid, sk_usuario FROM workspace.gold.dim_usuario
WHERE sk_usuario IN (-1, -2) OR usuario_uuid IN (
  SELECT usuario_uuid FROM workspace.silver.tb_usuario ORDER BY usuario_uuid LIMIT 5);
```

Run another update (no new data). Run the same query: every pair is identical, and
`data_carga` is later (the view was recomputed).
