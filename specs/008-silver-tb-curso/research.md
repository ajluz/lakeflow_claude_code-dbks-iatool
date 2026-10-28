# Research: Silver Course Catalog as the Latest Version of Each Course

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

Sources consulted: constitution v1.10.0; the `databricks-pipelines` skill
(`references/auto-cdc-sql.md`, `streaming-table-sql.md`, `expectations-sql.md`); feature
003 (`01_bronze/03_dados_database.sql`); feature 006's first design (an `AUTO CDC` target
declared with constraints only, accepted by the dry run); the generator
`generate_database_data` in `explorations/functions.py`; queries on the workspace
(profile `databricks-free`) on 2026-10-28.

## Facts established

| Fact | Value (2026-10-28) |
|---|---|
| Bronze columns | `processing_time timestamp, source_file_name string, curso_uuid string, nome_curso string, nivel_curso string, valor_curso double, change_type string, timestamp_change timestamp, _rescued_data string` |
| Rows | 3, all `insert`, one per course, all with `timestamp_change` `2026-10-11T22:42:09.713Z` |
| Prices | `247.0`, `997.0`, `2497.0` |
| Keys | `curso_uuid` = `md5(nome_curso)`; the same three values that `tb_acesso` and `tb_venda` carry (feature 007, `curso_fora` = 0) |
| Generator's later changes | `update row`: the beginner course to `147.00`; `delete row`: the same course, carrying its last values (`147.00`). Each is written in its own run with `current_timestamp()` |

## Decision 1: One view, as the diagram draws it

- **Decision**: `12_vw_bronze_tb_curso.sql` defines `vw_bronze_tb_curso` over
  `STREAM(workspace.bronze.dados_database)`: every column except `source_file_name`,
  `_rescued_data` and `valor_curso`, then `CAST(valor_curso AS DECIMAL(9,2)) AS
  valor_curso`, `'DATABASE' AS origem` and `current_timestamp() AS data_carga`.
- **Rationale**: the `AUTO CDC` source must be a named view or table, not a query
  (`auto-cdc-sql.md`). The diagram draws one view (`V5`) between the feed and `tb_curso`,
  under the name the owner chose. The earlier pipeline's `vw_bronze_tb_curso` already
  added `origem`. The future `dim_curso` must read the feed through this view with the
  same key, sequence and delete condition (Principle I), so it inherits the same price
  type and record source, and its current rows equal `tb_curso`'s.
- **Alternatives considered**: a pure boundary view plus a shaping view (an extra dataset
  the diagram does not draw, and a `double` price in gold); computing the columns in the
  flow (not possible in SQL).
- **Constitution**: deviates from Principle I and the naming rule; justified in the
  plan's Complexity Tracking, amendment pending.

## Decision 2: SCD type 1 with `AUTO CDC`

- **Decision**: one flow, `silver_tb_curso_flow`:

  ```text
  AUTO CDC INTO workspace.silver.tb_curso
  FROM STREAM(vw_bronze_tb_curso)
  KEYS (curso_uuid)
  APPLY AS DELETE WHEN change_type = 'delete'
  SEQUENCE BY timestamp_change
  COLUMNS * EXCEPT (change_type, timestamp_change, processing_time)
  STORED AS SCD TYPE 1
  ```
- **Rationale**: this is the request's "scd type 1" with deletions applied (spec FR-004,
  FR-005). `SEQUENCE BY` orders changes by when they happened, so a late older change does
  not overwrite a newer one (FR-006). The delete condition goes before `SEQUENCE BY`, as
  Principle V and the parser require. `COLUMNS * EXCEPT` removes the change-control
  columns and `processing_time` after they have driven the change (FR-003).
  `STORED AS SCD TYPE 1` is the default, written out so the plan's statement is visible
  in the code.
- **Alternatives considered**: `IGNORE NULL UPDATES` (not requested; every change in the
  feed carries all values); a `MERGE` (forbidden by Principle II).

## Decision 3: Ties in the sequence

- **Decision**: a single sequence column, `timestamp_change`.
- **Rationale**: a tie only matters for two changes to the same course with the same
  time. The generator writes each change in its own run, so it does not produce one. The
  three inserts share a time but have different keys.
- **Alternatives considered**: `SEQUENCE BY STRUCT(timestamp_change, processing_time)`.
  It would break ties by arrival, but rows of one file share `processing_time`, so it
  would not resolve a tie inside a file. Kept as a later change if a tie ever appears.

## Decision 4: Expectations on the `AUTO CDC` target

- **Decision**: three warn expectations on `tb_curso`: `check_curso_uuid`
  (`curso_uuid IS NOT NULL`), `check_nome_curso` (`nome_curso IS NOT NULL`),
  `check_valor_curso` (`valor_curso IS NOT NULL AND valor_curso > 0`).
- **Rationale**: the request names no rule; Principle III requires at least one. The
  target is declared with constraints only, as feature 006's first design was, which the
  dry run accepted. The metrics count the change rows the flow reads (3 today).
- **Expected failures**: 0 for each.

## Decision 5: The flow name

- **Decision**: unqualified `silver_tb_curso_flow`, like every other flow.
- **Rationale**: the open flow-name finding (flows appear under `workspace.bronze` in the
  event log) is the owner's to decide for all flows at once.

## Decision 6: What implementation proves

- **Decision**: implementation validates User Story 1 on the three inserts and leaves the
  update and deletion to the talk. The quickstart ends with the owner's script for them.
- **Rationale**: the owner's answer of 2026-10-28 (spec, Clarifications).
