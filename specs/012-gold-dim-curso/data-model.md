# Data Model: Gold Course Dimension (SCD Type 2)

## Lineage

```text
workspace.bronze.dados_database                      (change feed: insert / update / delete)
        │  vw_bronze_tb_curso                         (silver boundary view, unchanged:
        │                                               valor_curso DECIMAL(9,2), origem, data_carga)
        ├──► silver_tb_curso_flow ──► silver.tb_curso  (SCD 1, unchanged)
        ▼
vw_gold_dim_curso_dados_database                      (NEW flow view: sk_curso, no origem,
        │                                               no processing_time)
        │  gold_dim_curso_flow: AUTO CDC
        │   KEYS (curso_uuid)
        │   APPLY AS DELETE WHEN change_type = 'delete'
        │   SEQUENCE BY timestamp_change
        │   COLUMNS * EXCEPT (change_type, timestamp_change)
        │   STORED AS SCD TYPE 2
        ▼
workspace.gold.dim_curso  ◄── gold_dim_curso_membros_flow: AUTO CDC ONCE FROM SNAPSHOT
                                (members -1, -2; version TIMESTAMP'1900-01-01'; SCD TYPE 2)
```

## `vw_gold_dim_curso_dados_database` (temporary view)

| Column | Type | Expression |
|---|---|---|
| `sk_curso` | BIGINT | `xxhash64(curso_uuid, timestamp_change) & 9223372036854775807` |
| `curso_uuid` | STRING | feed, unchanged |
| `nome_curso` | STRING | feed, unchanged |
| `nivel_curso` | STRING | feed, unchanged |
| `valor_curso` | DECIMAL(9,2) | feed view, unchanged |
| `data_carga` | TIMESTAMP | feed view, unchanged |
| `change_type` | STRING | feed, unchanged; drives the delete, excluded by the flow |
| `timestamp_change` | TIMESTAMP | feed, unchanged; sequences the flow, excluded by it |

Source `STREAM(vw_bronze_tb_curso)`; no filter.

## `workspace.gold.dim_curso` (streaming table, SCD type 2)

Grain: one version of one course, plus two members. `quality` = `gold`. No expectations.

| # | Column | Type | Meaning |
|---|---|---|---|
| 1 | `sk_curso` | BIGINT | surrogate key of the version; non-negative for courses, `-1` / `-2` for members |
| 2 | `curso_uuid` | STRING | business key, the identifier delivered by the source |
| 3 | `nome_curso` | STRING | name |
| 4 | `nivel_curso` | STRING | level (`beginner`, `intermediate`, `advanced`) |
| 5 | `valor_curso` | DECIMAL(9,2) | price; empty for members |
| 6 | `data_carga` | TIMESTAMP | time gold wrote the version |
| 7 | `__START_AT` | TIMESTAMP | `timestamp_change` of the event that opened the version; `1900-01-01` for members |
| 8 | `__END_AT` | TIMESTAMP | `timestamp_change` of the event that closed it; empty while current |

### Members

| `sk_curso` | `curso_uuid` | `nome_curso` | `nivel_curso` | `valor_curso` | `__START_AT` | `__END_AT` |
|---|---|---|---|---|---|---|
| -1 | `-1` | Desconhecido | Desconhecido | empty | 1900-01-01 | empty |
| -2 | `-2` | Não se aplica | Não se aplica | empty | 1900-01-01 | empty |

### Version lifecycle (per `curso_uuid`)

| Event | Effect |
|---|---|
| insert (no open version) | opens a version: new `sk_curso`, `__START_AT` = change time |
| update | closes the open version (`__END_AT` = change time) and opens a new one with the new values and its own key |
| delete | closes the open version; nothing opens; no row is removed |
| insert after delete | opens a new version; closed ones stay |
| event older than the latest applied | placed in change-time order (out-of-order handling of `AUTO CDC`) |

### Invariants (checked by query)

- `sk_curso` is unique, never empty, and is `> 0` for every course row.
- `curso_uuid` is never empty.
- Each course has at most one row with `__END_AT IS NULL`.
- The current course rows equal `silver.tb_curso` in identifier, name, level and price.

## Expected rows (2026-11-05)

The feed holds 3 inserts, all at `2026-10-11 22:42:09.713` UTC. The dimension then has 3
open course rows and 2 members, 5 rows in all.

At the live demo:
- after `update row`, it has 6 rows (the updated course has a closed `247.00` version and
  an open `147.00` one);
- after `delete row`, it still has 6 rows, and the deleted course has no open version.
