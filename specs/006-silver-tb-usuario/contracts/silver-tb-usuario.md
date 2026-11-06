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
| `src/pipeline/02_silver/06_vw_silver_tb_usuario_api.sql` | `vw_silver_tb_usuario_api` (flow view) | `STREAM(workspace.silver.temp_tb_validacao_api)`, valid events with a user |
| `src/pipeline/02_silver/07_vw_silver_tb_usuario_files.sql` | `vw_silver_tb_usuario_files` (flow view) | `STREAM(vw_bronze_dados_files)` |
| `src/pipeline/02_silver/08_tb_usuario.sql` | `workspace.silver.tb_usuario` and its two flows | the two flow views |

## `02_vw_bronze_dados_files.sql`

`CREATE TEMPORARY VIEW vw_bronze_dados_files COMMENT '<Portuguese>' AS SELECT * EXCEPT (source_file_name, _rescued_data) FROM STREAM(workspace.bronze.dados_files)`.
Nothing else.

## Flow views and `08_tb_usuario.sql`

Each flow view selects exactly the 10 columns of the data model; the API view keeps the
`WHERE NOT fl_registro_invalido AND payload.info_usuario.nome IS NOT NULL` filter. Both
views write `sexo_usuario` as `CASE WHEN <sexo> IN ('M', 'F') THEN <sexo> END`, and
`check_sexo_usuario` only counts (owner, 2026-11-06).
Constitution v1.9.0 requires every append flow to read such a view.

```sql
CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_usuario (
  CONSTRAINT check_sexo_usuario  EXPECT (sexo_usuario IS NOT NULL AND sexo_usuario IN ('M', 'F')), -- ON VIOLATION DROP ROW
  CONSTRAINT check_email_usuario EXPECT (email_usuario IS NOT NULL AND email_usuario LIKE '%@%'),
  CONSTRAINT check_usuario_uuid  EXPECT (usuario_uuid IS NOT NULL)
)
COMMENT '<Portuguese>'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_usuario_api_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_tb_usuario_api);

CREATE FLOW silver_tb_usuario_files_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_tb_usuario_files);
```

Both flow views list the same 10 column names, in the same order and with the same
types. The API `usuario_uuid` expression in `06_vw_silver_tb_usuario_api.sql` is character
for character the same as in `05_tb_acesso.sql`.

## What a definition must not contain

| Forbidden | Why |
|---|---|
| `UNION` across the two sources; `AUTO CDC` | Principle V: one append flow per source; the owner's choice of append flows |
| any query logic in a flow beyond `SELECT * FROM STREAM(<flow view>)`; any view other than the two flow views | constitution v1.9.0 (flow views) and v1.8.0 (graph) |
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
