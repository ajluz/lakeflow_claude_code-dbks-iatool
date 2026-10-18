# Contract: Files Boundary View and the User Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-18 (revised for constitution v1.8.0)

Later features rely on the files boundary view and on `tb_usuario` with its key
expressions. This document fixes the shape of both definitions.

**Revision**: earlier versions had two shared key views (`vw_silver_eventos_api` and
`vw_silver_vendas_arquivo`) and two shaping views (`vw_silver_usuario_api` and
`vw_silver_usuario_arquivo`). They were removed under constitution v1.8.0: the silver
graph follows `doc/lakeflow_architecture.png`, and a key needs the same expression in
every table rather than a single shared definition. The first design also used
`AUTO CDC`, which the owner replaced with append flows.

## Files

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/02_vw_bronze_dados_files.sql` | `vw_bronze_dados_files` (temporary view) | `STREAM(workspace.bronze.dados_files)` |
| `src/pipeline/02_silver/06_tb_usuario.sql` | `workspace.silver.tb_usuario` and its two flows | `STREAM(workspace.silver.temp_tb_validacao_api)`, `STREAM(vw_bronze_dados_files)` |

## `02_vw_bronze_dados_files.sql`

`CREATE TEMPORARY VIEW vw_bronze_dados_files COMMENT '<Portuguese>' AS SELECT * EXCEPT (source_file_name, _rescued_data) FROM STREAM(workspace.bronze.dados_files)`.
Nothing else.

## `06_tb_usuario.sql`

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
SELECT <the 10 API columns of the data model>
FROM STREAM(workspace.silver.temp_tb_validacao_api)
WHERE NOT fl_registro_invalido
  AND payload.info_usuario.nome IS NOT NULL;

CREATE FLOW silver_tb_usuario_arquivo_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
SELECT <the 10 files columns of the data model>
FROM STREAM(vw_bronze_dados_files);
```

Both flows list the same 10 column names, in the same order and with the same types.
The API `usuario_uuid` expression is character for character the same as in
`05_tb_acesso.sql`.

## What a definition must not contain

| Forbidden | Why |
|---|---|
| `UNION` across the two sources; `AUTO CDC` | Principle V: one append flow per source; the owner's choice of append flows |
| a view between the validation table or `vw_bronze_dados_files` and `tb_usuario` | the graph of `doc/lakeflow_architecture.png` (constitution v1.8.0) |
| a read of `workspace.bronze.dados_files` outside `vw_bronze_dados_files`, or of bronze API data | Principle I; feature 004's consumer rule |
| anything in `vw_bronze_dados_files` beyond excluding the two lineage columns | Principle I |
| an API `usuario_uuid` expression that differs from `tb_acesso`'s | Principle VI (v1.8.0) |
| `uuid()`, `rand()` or a load time inside a key; bare `concat` | Principle VI |
| a materialized view, `PARTITIONED BY`, `CLUSTER BY` | Principle V |
| columns beyond the 10 in `tb_usuario` | FR-002 |

## What consumers may rely on

- `tb_usuario` holds one row per `usuario_uuid` (verified after each load), never null,
  with sex `M` or `F`.
- API rows join `tb_acesso` on `usuario_uuid`, apart from users whose access had the
  impossible address.
- Later sales tables MUST compute `usuario_uuid` with the same expressions: the API one
  above, and `md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, '')))`
  for the files. They MUST verify that their keys join `tb_usuario`.
