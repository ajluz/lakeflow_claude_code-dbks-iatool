# Contract: The Course Feed View and the Course Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-28

`gold.dim_curso` will read `vw_bronze_tb_curso` with the same key, sequence and delete
condition. Sales and accesses join `tb_curso` on `curso_uuid`.

## Files

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/12_vw_bronze_tb_curso.sql` | `vw_bronze_tb_curso` (temporary view) | `STREAM(workspace.bronze.dados_database)` |
| `src/pipeline/02_silver/13_tb_curso.sql` | `workspace.silver.tb_curso` and `silver_tb_curso_flow` | `STREAM(vw_bronze_tb_curso)` |

## `12_vw_bronze_tb_curso.sql`

```sql
CREATE TEMPORARY VIEW vw_bronze_tb_curso
COMMENT '<Portuguese>'
AS
SELECT
  * EXCEPT (source_file_name, _rescued_data, valor_curso),
  CAST(valor_curso AS DECIMAL(9,2)) AS valor_curso,
  'DATABASE'                         AS origem,
  current_timestamp()                AS data_carga
FROM STREAM(workspace.bronze.dados_database);
```

## `13_tb_curso.sql`

```sql
CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_curso (
  CONSTRAINT check_curso_uuid  EXPECT (curso_uuid IS NOT NULL),
  CONSTRAINT check_nome_curso  EXPECT (nome_curso IS NOT NULL),
  CONSTRAINT check_valor_curso EXPECT (valor_curso IS NOT NULL AND valor_curso > 0)
)
COMMENT '<Portuguese>'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_curso_flow AS AUTO CDC INTO workspace.silver.tb_curso
FROM STREAM(vw_bronze_tb_curso)
KEYS (curso_uuid)
APPLY AS DELETE WHEN change_type = 'delete'
SEQUENCE BY timestamp_change
COLUMNS * EXCEPT (change_type, timestamp_change, processing_time)
STORED AS SCD TYPE 1;
```

## What a definition must not contain

| Forbidden | Why |
|---|---|
| `APPLY CHANGES`, `LIVE`, `CREATE OR REPLACE`, `MERGE` | Principle II |
| a filter in the view, or any column change beyond the three above | constitution amendment scope (plan, Complexity Tracking) |
| the delete condition after `SEQUENCE BY` | Principle V; the parser |
| a hash key; `md5` | Principle VI exception for `tb_curso` |
| `ON VIOLATION DROP ROW` or `FAIL UPDATE` | spec FR-008: every rule only counts |
| `STORED AS SCD TYPE 2`, `TRACK HISTORY` | spec: SCD type 1 |
| `change_type`, `timestamp_change`, `processing_time`, `source_file_name`, `_rescued_data` as columns of `tb_curso` | spec FR-003 |
| `ai_*` functions | constitution v1.10.0 |

## What consumers may rely on

- `tb_curso` holds one row per `curso_uuid`, the latest non-deleted version, with
  `valor_curso` as `DECIMAL(9,2)` and `origem = 'DATABASE'`.
- `curso_uuid` equals `md5(nome_curso)`, the value sales and accesses carry.
- A deleted course has no row; its sales and accesses keep its key.
- A consumer that reads `tb_curso` as a stream needs `WITH (SKIPCHANGECOMMITS)`, because
  the table is updated and deleted in place (`streaming-table-sql.md`).
