# Contract: Files Source Views and the User Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-18

Later features rely on these: the boundary view and the shared view of the files source,
whose `usuario_uuid` sales tables must reuse, and `tb_usuario`, the conformed user table.
This document fixes the shape of the five definitions.

## Files

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/06_vw_bronze_dados_files.sql` | `vw_bronze_dados_files` | `STREAM(workspace.bronze.dados_files)` |
| `src/pipeline/02_silver/07_vw_silver_vendas_arquivo.sql` | `vw_silver_vendas_arquivo` | `STREAM(vw_bronze_dados_files)` |
| `src/pipeline/02_silver/08_vw_silver_usuario_api.sql` | `vw_silver_usuario_api` | `STREAM(vw_silver_eventos_api)` |
| `src/pipeline/02_silver/09_vw_silver_usuario_arquivo.sql` | `vw_silver_usuario_arquivo` | `STREAM(vw_silver_vendas_arquivo)` |
| `src/pipeline/02_silver/10_tb_usuario.sql` | `workspace.silver.tb_usuario` and its two flows | the two shaping views |

Every view is `CREATE TEMPORARY VIEW <name> COMMENT '<Portuguese>' AS SELECT ...`,
unqualified, with a header comment in Portuguese.

## The views

`06_vw_bronze_dados_files.sql`: `SELECT * EXCEPT (source_file_name, _rescued_data) FROM STREAM(workspace.bronze.dados_files)`. Nothing else.

`07_vw_silver_vendas_arquivo.sql`:

```sql
SELECT
  *,
  md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''))) AS usuario_uuid
FROM STREAM(vw_bronze_dados_files)
```

`08_vw_silver_usuario_api.sql`, select list in this order:

```sql
SELECT
  usuario_uuid,
  payload.info_usuario.nome                       AS nome_usuario,
  payload.info_usuario.email                      AS email_usuario,
  try_cast(payload.info_usuario.idade AS INT)     AS idade_usuario,
  payload.info_usuario.sexo                       AS sexo_usuario,
  payload.info_usuario.estado                     AS estado_usuario,
  payload.info_usuario.profissao                  AS profissao_usuario,
  CAST(NULL AS STRING)                            AS empresa_usuario,
  'API'                                           AS origem,
  current_timestamp()                             AS data_carga
FROM STREAM(vw_silver_eventos_api)
WHERE usuario_uuid IS NOT NULL
```

`09_vw_silver_usuario_arquivo.sql`: the same 10 columns in the same order, from
`nome_funcionario`, `email_funcionario`, `try_cast(idade AS INT)`, `sexo`, `estado`,
`profissao`, `nome_empresa`, `'ARQUIVO'` and `current_timestamp()`,
`FROM STREAM(vw_silver_vendas_arquivo)`.

## `10_tb_usuario.sql`

```sql
CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_usuario (
  CONSTRAINT check_sexo_usuario  EXPECT (sexo_usuario IS NOT NULL AND sexo_usuario IN ('M', 'F')) ON VIOLATION DROP ROW,
  CONSTRAINT check_email_usuario EXPECT (email_usuario IS NOT NULL AND email_usuario LIKE '%@%'),
  CONSTRAINT check_usuario_uuid  EXPECT (usuario_uuid IS NOT NULL)
)
COMMENT '<Portuguese>'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_usuario_api_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_usuario_api);

CREATE FLOW silver_tb_usuario_arquivo_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_usuario_arquivo);
```

Revised 2026-10-18: the first version used `AUTO CDC ... STORED AS SCD TYPE 1` flows with
a `sequencia` column. The owner replaced them with append flows (research, Decision 1).

Allowed fallback: if the dry run rejects constraints on a target with no column list, add
the 10 columns with their types (data-model.md) before the constraints.

## What a definition must not contain

| Forbidden | Why |
|---|---|
| a read of `workspace.bronze.dados_files` outside `vw_bronze_dados_files`, or of bronze API data | Principle I; feature 004's consumer rule |
| anything in `vw_bronze_dados_files` beyond excluding the two lineage columns | Principle I |
| a second definition of either `usuario_uuid` | Principle VI |
| `uuid()`, `rand()` or a load time inside a key; bare `concat` | Principle VI |
| `AUTO CDC`, `UNION` | append flows only (owner's decision, research Decision 1) |
| a materialized view, `PARTITIONED BY`, `CLUSTER BY` | Principle V |
| columns beyond the 10 in `tb_usuario` | FR-002 |
| `LIVE`, `CREATE OR REPLACE`, `APPLY CHANGES` | Principle II |
| a file without its `NN_` prefix | Principle V |

## What consumers may rely on

- `tb_usuario` holds one row per `usuario_uuid` (verified after each load), never null, with sex `M` or `F`.
- API rows join `tb_acesso` on `usuario_uuid`.
- Later sales tables from the files source MUST read `vw_silver_vendas_arquivo` and reuse
  its `usuario_uuid`. Sales from the API MUST reuse `vw_silver_eventos_api`'s.

## Mapping to the specification

| Spec item | Covered by |
|---|---|
| FR-001, FR-005 | two flows into one target |
| FR-002 | the shaping views' select lists |
| FR-003 | `vw_silver_usuario_api` reads `vw_silver_eventos_api` and its key |
| FR-004 | `vw_silver_vendas_arquivo` |
| FR-006 | `vw_bronze_dados_files` |
| FR-007 | unique keys in the data; uniqueness check in the quickstart |
| FR-008, FR-009 | `check_sexo_usuario ... DROP ROW`; declared exclusion documented |
| FR-010 | `check_email_usuario` warn |
| FR-011 | `check_usuario_uuid` |
| FR-012 | property |
| FR-013 | streaming reads |
| FR-014 | files table |
| FR-015 | documentation tasks (see plan) |
