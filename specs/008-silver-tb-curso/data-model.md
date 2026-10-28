# Data Model: Silver Course Catalog as the Latest Version of Each Course

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

```text
workspace.bronze.dados_database
        │ STREAM
        ▼
vw_bronze_tb_curso   (V5: drops source_file_name, _rescued_data;
        │             valor_curso → DECIMAL(9,2); adds origem, data_carga)
        │ AUTO CDC (silver_tb_curso_flow)
        │   KEYS (curso_uuid)
        │   APPLY AS DELETE WHEN change_type = 'delete'
        │   SEQUENCE BY timestamp_change
        │   COLUMNS * EXCEPT (change_type, timestamp_change, processing_time)
        │   STORED AS SCD TYPE 1
        ▼
workspace.silver.tb_curso   (S5: streaming table, 3 warn expectations)
```

## `vw_bronze_tb_curso` (temporary view)

| Column | Type | From |
|---|---|---|
| `processing_time` | TIMESTAMP | bronze, unchanged |
| `curso_uuid` | STRING | bronze, unchanged |
| `nome_curso` | STRING | bronze, unchanged |
| `nivel_curso` | STRING | bronze, unchanged |
| `change_type` | STRING | bronze, unchanged |
| `timestamp_change` | TIMESTAMP | bronze, unchanged |
| `valor_curso` | DECIMAL(9,2) | `CAST(valor_curso AS DECIMAL(9,2))` |
| `origem` | STRING | `'DATABASE'` |
| `data_carga` | TIMESTAMP | `current_timestamp()` |

No filter. `source_file_name` and `_rescued_data` are excluded.

## `workspace.silver.tb_curso`

| Column | Type | Rule |
|---|---|---|
| `curso_uuid` | STRING | `KEYS`; `check_curso_uuid`: not null (warn); one row per value |
| `nome_curso` | STRING | `check_nome_curso`: not null (warn) |
| `nivel_curso` | STRING | — |
| `valor_curso` | DECIMAL(9,2) | `check_valor_curso`: not null and > 0 (warn) |
| `origem` | STRING | `'DATABASE'` |
| `data_carga` | TIMESTAMP | load time of the change that last set the row |

Exactly these 6 columns. Column order follows the view, minus the excluded columns;
planning accepts whatever order `COLUMNS * EXCEPT` produces, and the quickstart records
it.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, `AUTO CDC` target, **SCD type 1** | FR-004 |
| Key | `curso_uuid`, the source identifier (no hash key, Principle VI exception) | FR-011 |
| Sequence | `timestamp_change` | FR-006 |
| Delete condition | `change_type = 'delete'` | FR-005 |
| `quality` | `silver` | FR-009 |

## State of a course

```text
(no row) --insert--> current row --update--> current row (values overwritten, new data_carga)
current row --delete--> (no row) --insert, later time--> current row
```

A change older than the course's latest applied change does not alter the row.

## Expected rows

| Point | Rows | Beginner course |
|---|---|---|
| Now (three inserts) | 3 | `247.00` |
| Talk, after `update row` | 3 | `147.00` |
| Talk, after `delete row` | 2 | absent |
