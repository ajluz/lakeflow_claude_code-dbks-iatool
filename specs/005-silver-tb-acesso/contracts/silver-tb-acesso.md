# Contract: The Access Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-18 (revised for constitution v1.8.0)

Later features rely on `tb_acesso` and on its key expressions. This document fixes the
shape of its single definition.

**Revision**: the first version had a shared view, `04_vw_silver_eventos_api.sql`, which
held `timestamp_acesso`, `usuario_uuid` and `curso_uuid`. Under constitution v1.8.0 the
silver graph follows `doc/lakeflow_architecture.png`, and a key needs the same expression
in every table, not a single shared definition. The view was removed, and `tb_acesso`
reads the validation table directly and computes its keys inline.

## File

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/05_tb_acesso.sql` | `workspace.silver.tb_acesso` | `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE NOT fl_registro_invalido` |

## `05_tb_acesso.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_acesso` |
| Column list | the expectations below, in this order |
| Description | a `COMMENT` in Portuguese |
| Property | `TBLPROPERTIES ("quality" = "silver")` |
| Select list, in order | `try_to_timestamp(access_date) AS timestamp_acesso`; `ip_address AS endereco_ip_acesso`; the `local_acesso` `CASE`; `acesso_uuid`; `usuario_uuid`; `curso_uuid`; `'API' AS origem`; `current_timestamp() AS data_carga`, with the expressions of [../data-model.md](../data-model.md) |
| Source | `FROM STREAM(workspace.silver.temp_tb_validacao_api) WHERE NOT fl_registro_invalido` |

```sql
CONSTRAINT check_endereco_ip_acesso EXPECT (endereco_ip_acesso IS NULL OR endereco_ip_acesso != '999.999.999.999') ON VIOLATION DROP ROW,
CONSTRAINT check_local_acesso       EXPECT (local_acesso != 'unknown'),
-- CONSTRAINT check_local_acesso    EXPECT (local_acesso != 'unknown') ON VIOLATION FAIL UPDATE,
CONSTRAINT check_timestamp_acesso   EXPECT (timestamp_acesso IS NOT NULL),
CONSTRAINT check_acesso_uuid        EXPECT (acesso_uuid IS NOT NULL)
```

The `usuario_uuid` expression must be **character for character** the same as in
`06_tb_usuario.sql`:

```sql
md5(concat_ws('||', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome))
```

## What the definition must not contain

| Forbidden | Why |
|---|---|
| a read of bronze, of `tb_quarentena`, or of the validation table without `WHERE NOT fl_registro_invalido` | feature 004's consumer rule; Principle I |
| a view between the validation table and `tb_acesso` | the graph of `doc/lakeflow_architecture.png` (constitution v1.8.0) |
| a `usuario_uuid` expression that differs from `tb_usuario`'s | Principle VI (v1.8.0): one expression per key |
| `uuid()`, `rand()` or a load time inside a key; bare `concat` | Principle VI |
| `ON VIOLATION FAIL UPDATE` active | the request: informative only |
| a materialized view, `PARTITIONED BY`, `CLUSTER BY` | Principle V |
| columns beyond the 8 of the data model | FR-002 |

## What consumers may rely on

- One row per valid API access whose address is not `999.999.999.999`. `acesso_uuid`
  is non-null and unique.
- `usuario_uuid` joins `tb_usuario`. `curso_uuid` joins `tb_curso` and `dim_curso`.
- A later table that computes `usuario_uuid` or `curso_uuid` for API events MUST use the
  same expressions and verify that its keys join (Principle VI, v1.8.0).
