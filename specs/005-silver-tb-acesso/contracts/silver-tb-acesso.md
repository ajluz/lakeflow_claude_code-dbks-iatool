# Contract: Shared View of Valid API Events and the Access Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-18

Later features rely on two things: the shared view, which defines the API source's
reference keys once, and `tb_acesso`, the conformed access table. This document fixes
the shape of both definitions.

## Files

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/04_vw_silver_eventos_api.sql` | `vw_silver_eventos_api` (temporary view) | `STREAM(workspace.silver.temp_tb_validacao_api)` |
| `src/pipeline/02_silver/05_tb_acesso.sql` | `workspace.silver.tb_acesso` | `STREAM(vw_silver_eventos_api)` |

## `04_vw_silver_eventos_api.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE TEMPORARY VIEW vw_silver_eventos_api`, unqualified |
| Description | a `COMMENT` in Portuguese |
| Select list, in order | `*`; `try_to_timestamp(access_date) AS timestamp_acesso`; `usuario_uuid`; `curso_uuid`, with the expressions of [../data-model.md](../data-model.md#vw_silver_eventos_api-shared-view-of-valid-api-events) |
| Source | `FROM STREAM(workspace.silver.temp_tb_validacao_api) WHERE NOT fl_registro_invalido` |

`usuario_uuid` uses `timestamp_acesso`, an alias defined earlier in the same select list
(a lateral column alias, accepted in feature 004). If a run rejects it, compute
`timestamp_acesso` in a subquery.

## `05_tb_acesso.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_acesso` |
| Column list | the expectations below, in this order |
| Description | a `COMMENT` in Portuguese |
| Property | `TBLPROPERTIES ("quality" = "silver")` |
| Select list, in order | `timestamp_acesso`; `ip_address AS endereco_ip_acesso`; the `local_acesso` `CASE`; `acesso_uuid`; `usuario_uuid`; `curso_uuid`; `'API' AS origem`; `current_timestamp() AS data_carga` |
| Source | `FROM STREAM(vw_silver_eventos_api)` and nothing else |

Expectations, in this order:

```sql
CONSTRAINT check_endereco_ip_acesso EXPECT (endereco_ip_acesso IS NULL OR endereco_ip_acesso != '999.999.999.999') ON VIOLATION DROP ROW,
CONSTRAINT check_local_acesso       EXPECT (local_acesso != 'unknown'),
-- CONSTRAINT check_local_acesso    EXPECT (local_acesso != 'unknown') ON VIOLATION FAIL UPDATE,
CONSTRAINT check_timestamp_acesso   EXPECT (timestamp_acesso IS NOT NULL),
CONSTRAINT check_acesso_uuid        EXPECT (acesso_uuid IS NOT NULL)
```

The commented line sits right after the active `check_local_acesso`. To switch on the
stopping rule, comment out the active line and uncomment the other. Each file has a
header comment in Portuguese that names the three actions and says the drop is a declared
exclusion, not quarantined.

## What a statement must not contain

| Forbidden | Why |
|---|---|
| a read of bronze, of `tb_quarentena`, or of the validation table without `WHERE NOT fl_registro_invalido` | feature 004's consumer rule; Principle I |
| `uuid()`, `rand()`, `current_timestamp()` or `data_carga` inside a key | Principle VI: deterministic keys |
| bare `concat` in a multi-column key | Principle VI |
| a second definition of `usuario_uuid` or `curso_uuid` | Principle VI: one definition per key |
| `ON VIOLATION FAIL UPDATE` active | the request: informative only |
| a materialized view | Principle V: silver is streaming |
| `PARTITIONED BY`, `CLUSTER BY` | Principle V; no layout need |
| columns beyond the 8 of the data model | FR-002 |
| `LIVE`, `CREATE OR REPLACE`, `APPLY CHANGES`, `CREATE FLOW` | Principle II; single source |
| a file without its `NN_` prefix | Principle V |

## What consumers may rely on

- `tb_acesso` holds one row per valid API access whose address is not
  `999.999.999.999`. `acesso_uuid` is non-null and unique.
- `curso_uuid` joins `workspace.silver.tb_curso` and `gold.dim_curso` on the catalog's
  identifier.
- Later silver tables built from API events (users, sales) MUST read
  `STREAM(vw_silver_eventos_api)` and reuse its `timestamp_acesso`, `usuario_uuid` and
  `curso_uuid`, never recompute them.

## Mapping to the specification

| Spec item | Covered by |
|---|---|
| FR-001 | view source and `WHERE NOT fl_registro_invalido` |
| FR-002 | `tb_acesso` select list |
| FR-003, FR-005 | key expressions (data model) and the forbidden list |
| FR-004 | `curso_uuid` = `md5(product_name)` |
| FR-006, FR-007 | `check_endereco_ip_acesso ... DROP ROW`; declared exclusion documented |
| FR-008, FR-009 | `check_local_acesso` warn plus the commented `FAIL UPDATE` line |
| FR-010 | `check_acesso_uuid`; uniqueness check in the quickstart |
| FR-011 | `IS NULL OR` in the address rule; `ELSE 'unknown'` in the mapping |
| FR-012 | property row |
| FR-013 | streaming reads |
| FR-014 | reconciliation in [../quickstart.md](../quickstart.md) |
| FR-015 | files table |
| FR-016 | documentation tasks (see plan) |
