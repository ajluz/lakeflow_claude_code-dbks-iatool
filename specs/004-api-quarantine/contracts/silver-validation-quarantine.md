# Contract: API Boundary View, Validation Table and Quarantine Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-18 (revised for constitution v1.6.0)

The feature exposes what later features rely on. The validation table is the split point
for every conformed silver table built from API events, and the quarantine table holds
the rejected ones. This document fixes the shape of the three definitions and the
renaming of the bronze files.

## Files

One file per dataset, each holding exactly one statement, named `NN_<dataset>.sql` and
numbered from `01` within its zone folder (constitution v1.6.0, Principle V).

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/01_vw_bronze_dados_api.sql` | `vw_bronze_dados_api` (temporary view) | `STREAM(workspace.bronze.dados_api)` |
| `src/pipeline/02_silver/03_temp_tb_validacao_api.sql` | `workspace.silver.temp_tb_validacao_api` | `STREAM(vw_bronze_dados_api)` |
| `src/pipeline/02_silver/04_tb_quarentena.sql` | `workspace.silver.tb_quarentena` | `STREAM(workspace.silver.temp_tb_validacao_api)` |

Bronze renames, with content unchanged:

| From | To |
|---|---|
| `src/pipeline/01_bronze/dados_api.sql` | `src/pipeline/01_bronze/01_dados_api.sql` |
| `src/pipeline/01_bronze/dados_files.sql` | `src/pipeline/01_bronze/02_dados_files.sql` |
| `src/pipeline/01_bronze/dados_database.sql` | `src/pipeline/01_bronze/03_dados_database.sql` |

The pipeline globs `src/pipeline/**`, so the renames change no dataset. In the workspace,
the old unnumbered bronze files MUST be deleted after the upload. Otherwise each bronze
table would be defined twice and the update would fail.

## `01_vw_bronze_dados_api.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE TEMPORARY VIEW vw_bronze_dados_api`, unqualified: temporary views are pipeline-scoped, not persisted |
| Description | a `COMMENT` in Portuguese |
| Select list | `* EXCEPT (source_file_name, _rescued_data)` and nothing else |
| Source | `FROM STREAM(workspace.bronze.dados_api)` and nothing else |

## `03_temp_tb_validacao_api.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api` |
| Column list | only the three `CONSTRAINT` clauses of [../data-model.md](../data-model.md#validation-rules), in that order, with that text, each without `ON VIOLATION` |
| Layout | `PARTITIONED BY (fl_registro_invalido)`, the plan's recorded exception to Principle V |
| Description | a `COMMENT` in Portuguese |
| Property | `TBLPROPERTIES ("quality" = "silver")` |
| Select list, in order | `*`; `regras_violadas`; `size(regras_violadas) > 0 AS fl_registro_invalido`; `'API' AS origem`; `current_timestamp() AS data_carga` |
| `regras_violadas` | `filter(array(...), r -> r IS NOT NULL)`, one `CASE WHEN NOT (<condition>) THEN '<name>' END` per rule, in the same order and with the same conditions as the `CONSTRAINT` clauses |
| Source | `FROM STREAM(vw_bronze_dados_api)` and nothing else |

The flag reuses `regras_violadas`, an alias defined earlier in the same select list.
Databricks SQL resolves such lateral column aliases; a batch run on the SQL warehouse and
the validate-only run of 2026-10-18 both accepted it. If a later run rejects it, build the
array in a subquery in the `FROM` clause and derive the flag outside it. The contract fixes
the resulting columns, not the form.

## `04_tb_quarentena.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_quarentena` |
| Column list | one clause: `CONSTRAINT regra_violada_registrada EXPECT (size(regras_violadas) > 0)`, without `ON VIOLATION` |
| Description | a `COMMENT` in Portuguese |
| Property | `TBLPROPERTIES ("quality" = "silver")` |
| Select list | `*` (every column of the validation table, nothing excluded or replaced), then `current_timestamp() AS data_carga_quarentena` |
| Source | `FROM STREAM(workspace.silver.temp_tb_validacao_api) WHERE fl_registro_invalido` |

## What a statement must not contain

| Forbidden | Why |
|---|---|
| `source_file_name` or `_rescued_data` in either silver table | constitution v1.6.0, Principle I; FR-002a |
| a read of `workspace.bronze.dados_api` anywhere except the boundary view | Principle I: every zone change goes through the view |
| a filter, cast, rename or rule in the boundary view | Principle I: the view only excludes the lineage columns |
| `ON VIOLATION DROP ROW` or `FAIL UPDATE` on any rule | rules only measure; the split is done by the flag (FR-005) |
| `CLUSTER BY` on the validation table | rejected by the platform for `BOOLEAN` columns (research, Decision 2) |
| `PARTITIONED BY` in the view or in the quarantine file | Principle V; the exception covers only the validation table |
| `CAST` or renames of a delivered column | the event is preserved (FR-002, FR-010) |
| `EXCEPT` in the quarantine select list | every validation column is kept (FR-012a; Principle IV) |
| `DISTINCT`, `GROUP BY`, joins, a `WHERE` in the view or the validation table | validation removes nothing (FR-002) |
| `CREATE FLOW` | single source per table |
| `LIVE`, `CREATE OR REPLACE`, `APPLY CHANGES` | legacy or non-pipeline syntax (Principle II) |
| a catalog other than `workspace`, or an unqualified persisted table name | constitution, catalog constraint (the temporary view is not persisted) |
| a rule written differently in the `CONSTRAINT` clause and in `regras_violadas` | Principle IV: the flag and the expectations encode the same predicates |
| a file name without the `NN_` prefix | Principle V |

## What consumers may rely on

Conformed silver tables built from API events in later features:

- MUST read `STREAM(workspace.silver.temp_tb_validacao_api)` with
  `WHERE NOT fl_registro_invalido`, and nothing else from this source.
- May rely on `fl_registro_invalido` never being `NULL`, on `origem = 'API'`, and on every
  column of the boundary view being present unchanged.
- MUST NOT restate the rules: the flag is the decision.

Anyone inspecting rejected data:

- May query `workspace.silver.tb_quarentena`. Each row carries every column of the
  validation table: one bronze event, without `source_file_name` and `_rescued_data`,
  otherwise unchanged; `regras_violadas` naming at least one of `curso_invalido`,
  `valor_invalido`, `forma_pagamento_invalido`; `fl_registro_invalido`, `origem`,
  `data_carga` (validation time); and `data_carga_quarentena`.
  The source file of a quarantined row can be found in bronze by matching its other
  columns.
- Rows are only ever added.

The validation table cannot be queried outside the pipeline, because it is private. Its
counts are read from the pipeline event log.

## Changing a rule

A rule change edits both its `CONSTRAINT` clause and its `CASE` line in the same commit,
and updates [../data-model.md](../data-model.md) and `doc/pipeline-reference.md`. Rows
already validated are not re-evaluated unless the owner approves a full refresh.

## Mapping to the specification

| Spec item | Covered by |
|---|---|
| FR-001, FR-002, FR-002a | the view and the validation statement; forbidden list |
| FR-003, FR-006, FR-007 | `regras_violadas` and the flag derived from it |
| FR-004, FR-005 | the three `CONSTRAINT` clauses |
| FR-008 | layout row |
| FR-009, FR-010, FR-011 | quarantine statement |
| FR-012, FR-012a | `origem` and `data_carga` in the validation select list; `*` and `data_carga_quarentena` in the quarantine select list |
| FR-013 | reconciliation in [../quickstart.md](../quickstart.md) |
| FR-014 | "what consumers may rely on" |
| FR-015 | streaming reads over `STREAM(...)` |
| FR-016 | property rows |
| FR-017, FR-017a | files table and bronze renames |
| FR-018 | documentation tasks (see plan) |
