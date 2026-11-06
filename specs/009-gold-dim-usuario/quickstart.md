# Quickstart: Validate the User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28, revised 2026-11-04 and 2026-11-05

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

## 6. Inferred users (2026-11-05, FR-013)

**Undone 2026-11-06 (owner).** The inferred-users revision below was implemented (update
`4d2eebb5`) and then reverted. The view `vw_gold_dim_usuario_tb_venda` and the flow
`gold_dim_usuario_tb_venda_flow` were removed, and the gold files are back to `01_`–`07_`. A full
refresh of `dim_usuario` only (update `8d27cdf5`, approved by the owner) cleared the 4,362
placeholder rows. `dim_usuario` is back to 941,236 rows with unchanged keys. The text that follows
is kept as history.


### Before the change

Record the current dimension:

```sql
SELECT count(*) AS linhas,                                                     -- 941236
       sum(hash(sk_usuario, usuario_uuid, nome_usuario, email_usuario, idade_usuario,
                sexo_usuario, estado_usuario, profissao_usuario, empresa_usuario,
                origem, data_carga)) AS checksum
FROM workspace.gold.dim_usuario;

SELECT count(DISTINCT v.usuario_uuid) AS faltantes                            -- 4362
FROM workspace.silver.tb_venda v
LEFT ANTI JOIN workspace.silver.tb_usuario u ON u.usuario_uuid = v.usuario_uuid;
```

### Switch-over

1. Delete the six renamed files' old names from the workspace (`02_dim_usuario.sql`,
   `03_dim_codigos.sql`, `04_vw_gold_dim_curso_dados_database.sql`,
   `05_vw_gold_dim_curso_membros.sql`, `06_dim_curso.sql`, `07_fato_venda.sql`).
2. Upload `src/pipeline`.
3. Confirm that `03_gold` holds exactly the eight files `01_` to `08_`, each identical to the
   repository.

Then run a dry run and a **real** ordinary update, which is the proof (contract). Both must
end `COMPLETED`, with no full refresh.

### After the update

```sql
SELECT count(*) AS linhas,                                                     -- 945598
       count(DISTINCT sk_usuario) AS chaves,                                   -- 945598
       count_if(sk_usuario > 0 AND nome_usuario = 'Desconhecido') AS inferidos, -- 4362
       count_if(sk_usuario < 0) AS membros                                     -- 2
FROM workspace.gold.dim_usuario;

-- coverage: every sale's user has a row (constitution v3.1.0)
SELECT count(*) AS vendas_sem_usuario                                         -- 0
FROM workspace.silver.tb_venda v
LEFT ANTI JOIN workspace.gold.dim_usuario d ON d.usuario_uuid = v.usuario_uuid;

-- inferred rows: labels, origem from the sale, same key expression
SELECT count_if(origem <> 'API') AS origem_errada,                             -- 0
       count_if(sk_usuario <> xxhash64(usuario_uuid) & 9223372036854775807) AS chave_errada, -- 0
       count_if(idade_usuario IS NOT NULL OR email_usuario <> 'Desconhecido') AS rotulo_errado -- 0
FROM workspace.gold.dim_usuario
WHERE sk_usuario > 0 AND nome_usuario = 'Desconhecido';
```

The checksum of step "Before the change", restricted to rows that are neither inferred nor
members, is unchanged: the silver users and their `data_carga` were not rewritten. A second
ordinary update leaves the 945,598 rows and the full checksum unchanged.

`fato_venda` (08) still uses its `LEFT JOIN`, so its counts are unchanged. Its
`sk_usuario = -1` stays at 4,362: those sales were written before the inferred rows existed,
and keys are resolved once (feature 013). Switching the fact to inner joins, and
re-resolving those sales, is feature 013's revision.
