# Data Model: Gold Course Dimension (SCD Type 2)

Revised 2026-11-05: members come from a view through a once-only flow (research,
Decision 9).

## Lineage

```text
workspace.bronze.dados_database                      (change feed: insert / update / delete)
        │  vw_bronze_tb_curso                         (silver boundary view, unchanged)
        ├──► silver_tb_curso_flow ──► silver.tb_curso  (SCD 1, unchanged)
        ▼
vw_gold_dim_curso_dados_database                      (flow view: sk_curso; no origem, no processing_time)
        │  gold_dim_curso_flow: AUTO CDC
        │   KEYS (curso_uuid)
        │   APPLY AS DELETE WHEN change_type = 'delete'
        │   SEQUENCE BY timestamp_change
        │   COLUMNS * EXCEPT (change_type, timestamp_change)
        │   STORED AS SCD TYPE 2
        ▼
workspace.gold.dim_curso  ◄── gold_dim_curso_membros_flow: AUTO CDC ONCE (same clauses)
                                 ▲
                          vw_gold_dim_curso_membros   (members -1 / -2, timestamp_change 1900-01-01)
```

## `vw_gold_dim_curso_dados_database` (temporary view, exists)

| Column | Type | Expression |
|---|---|---|
| `sk_curso` | BIGINT | `xxhash64(curso_uuid, timestamp_change) & 9223372036854775807` |
| `curso_uuid`, `nome_curso`, `nivel_curso` | STRING | feed, unchanged |
| `valor_curso` | DECIMAL(9,2) | feed view, unchanged |
| `data_carga` | TIMESTAMP | feed view, unchanged |
| `change_type` | STRING | feed; drives the delete; excluded by the flow |
| `timestamp_change` | TIMESTAMP | feed; sequences the flow; excluded by it |

## `vw_gold_dim_curso_membros` (temporary view, new)

The same 8 columns, in the same order, with two literal rows:

| `sk_curso` | `curso_uuid` | `nome_curso` | `nivel_curso` | `valor_curso` | `data_carga` | `change_type` | `timestamp_change` |
|---|---|---|---|---|---|---|---|
| -1 | `-1` | Desconhecido | Desconhecido | NULL (DECIMAL(9,2)) | `current_timestamp()` | `insert` | 1900-01-01 |
| -2 | `-2` | Não se aplica | Não se aplica | NULL (DECIMAL(9,2)) | `current_timestamp()` | `insert` | 1900-01-01 |

The rows are written as literals. In the streaming variant they are also cross-joined to
`STREAM(vw_bronze_tb_curso)`; see research, Decision 9.

## `workspace.gold.dim_curso` (streaming table, SCD type 2)

Grain: one version of one course, plus two members. `quality` = `gold`. No expectations.

| # | Column | Type | Meaning |
|---|---|---|---|
| 1 | `sk_curso` | BIGINT | surrogate key of the version; positive for courses, `-1` / `-2` for members |
| 2 | `curso_uuid` | STRING | business key, the identifier delivered by the source |
| 3 | `nome_curso` | STRING | name |
| 4 | `nivel_curso` | STRING | level (`beginner`, `intermediate`, `advanced`) |
| 5 | `valor_curso` | DECIMAL(9,2) | price; empty for members |
| 6 | `data_carga` | TIMESTAMP | time gold wrote the version |
| 7 | `__START_AT` | TIMESTAMP | `timestamp_change` of the opening event; `1900-01-01` for members |
| 8 | `__END_AT` | TIMESTAMP | `timestamp_change` of the closing event; empty while current |

### Version lifecycle (per `curso_uuid`)

| Event | Effect |
|---|---|
| insert (no open version) | opens a version: new `sk_curso`, `__START_AT` = change time |
| update | closes the open version (`__END_AT` = change time) and opens a new one with its own key |
| delete | closes the open version; nothing opens; no row is removed |
| insert after delete | opens a new version; closed ones stay |
| event older than the latest applied | placed in change-time order |

Members are written once and never receive another event, so they stay open.

### Invariants (checked by query)

- `sk_curso` is unique, never empty, and `> 0` for every course row.
- `curso_uuid` is never empty.
- Each `curso_uuid` has at most one row with `__END_AT IS NULL`. Each member has exactly
  one row.
- The current course rows equal `silver.tb_curso` in identifier, name, level and price.

## Expected rows (2026-11-05)

- 3 course rows, from update `3f2c2771`, with key checksum `-380130840`, plus 2 members:
  5 rows.
- At the live demo:
  - after `update row`, there are 6 rows: a closed `247.00` version and an open `147.00`
    one;
  - after `delete row`, there are still 6 rows, and the deleted course has no open
    version.
