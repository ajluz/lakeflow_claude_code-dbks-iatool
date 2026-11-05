# Quickstart: Validate the User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28, revised 2026-11-04

Shapes are in [data-model.md](data-model.md) and
[contracts/gold-dim-usuario.md](contracts/gold-dim-usuario.md). Every CLI command takes
`--profile databricks-free`. `<pipeline_id>` is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.

## Prerequisites

- `src/pipeline/03_gold/01_vw_gold_dim_usuario_tb_usuario.sql` and `02_dim_usuario.sql` exist.
- Do not run the generators: the course demo must reach the talk in its initial state
  (feature 008).
- **Free Edition**: stop the SQL warehouse (`databricks warehouses stop f796ffb64302b6ba`)
  only when no query is running, and wait about 4 minutes after the previous update.

## 1. Before the run

```sql
SELECT count(*) AS usuarios, count(DISTINCT usuario_uuid) AS chaves,
       count(DISTINCT xxhash64(usuario_uuid) & 9223372036854775807) AS sk_distintas,
       count_if(data_carga IS NULL) AS sequencia_nula
FROM workspace.silver.tb_usuario;
```

Expected: 941,234, 941,234, 941,234 (no hash collision), and 0 null sequence values.

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` | `03_gold/` lists the two new files as `FILE` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile databricks-free` | `COMPLETED`; `workspace.gold.dim_usuario` defined |
| Run | `databricks pipelines start-update <pipeline_id> --profile databricks-free` | `COMPLETED`, no failed flow. A completed dry run does not guarantee this |

## 3. Contents of `dim_usuario`

```sql
SELECT count(*) AS linhas,
       count(DISTINCT sk_usuario) AS sk, count(DISTINCT usuario_uuid) AS bk,
       count_if(sk_usuario IS NULL OR usuario_uuid IS NULL) AS chave_vazia,
       count_if(sk_usuario < 0) AS membros,
       count_if(origem = 'API') AS api, count_if(origem = 'ARQUIVO') AS arquivo
FROM workspace.gold.dim_usuario;

-- Members: the only rows with a negative key
SELECT * FROM workspace.gold.dim_usuario WHERE sk_usuario < 0 ORDER BY sk_usuario DESC;

-- Attributes equal silver's
SELECT count(*) AS divergentes
FROM workspace.silver.tb_usuario s
JOIN workspace.gold.dim_usuario d USING (usuario_uuid)
WHERE NOT (s.nome_usuario <=> d.nome_usuario AND s.email_usuario <=> d.email_usuario
       AND s.idade_usuario <=> d.idade_usuario AND s.sexo_usuario <=> d.sexo_usuario
       AND s.estado_usuario <=> d.estado_usuario AND s.profissao_usuario <=> d.profissao_usuario
       AND s.empresa_usuario <=> d.empresa_usuario AND s.origem <=> d.origem
       AND d.sk_usuario = (xxhash64(s.usuario_uuid) & 9223372036854775807));

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

None: the dimension declares no expectations (FR-008). Step 3's `chave_vazia`, `sk` and `bk`
verify the keys.

## 5. Key stability

Before the second update, save a sample:

```sql
SELECT usuario_uuid, sk_usuario, data_carga FROM workspace.gold.dim_usuario
WHERE sk_usuario < 0 OR usuario_uuid IN (
  SELECT usuario_uuid FROM workspace.silver.tb_usuario ORDER BY usuario_uuid LIMIT 5);
```

Run another update (no new data). Run the same query: every row is identical, `data_carga`
included (`AUTO CDC` rewrites nothing when no silver row arrives), and the row count is
still 941,236.
