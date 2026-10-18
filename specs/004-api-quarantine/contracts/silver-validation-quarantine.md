# Contract: API Validation Table and Quarantine Table

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-18

The feature exposes two things that later features rely on: the validation table, which is
the split point for every conformed silver table built from API events, and the quarantine
table. This document fixes the shape of both definitions.

## Files

One file per table, each holding exactly one statement.

| File | Table | Reads |
|---|---|---|
| `src/pipeline/02_silver/temp_tb_validacao_api.sql` | `workspace.silver.temp_tb_validacao_api` | `STREAM(workspace.bronze.dados_api)` |
| `src/pipeline/02_silver/tb_quarentena.sql` | `workspace.silver.tb_quarentena` | `STREAM(workspace.silver.temp_tb_validacao_api)` |

## `temp_tb_validacao_api.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api` |
| Column list | only the four `CONSTRAINT` clauses of [../data-model.md](../data-model.md#validation-rules), in that order, with that text, each without `ON VIOLATION` |
| Layout | `CLUSTER BY (fl_registro_invalido)` |
| Description | a `COMMENT` in Portuguese |
| Property | `TBLPROPERTIES ("quality" = "silver")` |
| Select list, in order | `*`; `regras_violadas`; `size(regras_violadas) > 0 AS fl_registro_invalido`; `'API' AS origem`; `current_timestamp() AS data_carga` |
| `regras_violadas` | `filter(array(...), r -> r IS NOT NULL)`, one `CASE WHEN NOT (<condition>) THEN '<name>' END` per rule, in the same order and with the same conditions as the `CONSTRAINT` clauses |
| Source | `FROM STREAM(workspace.bronze.dados_api)` and nothing else |

The flag reuses `regras_violadas`, an alias defined earlier in the same select list.
Databricks SQL resolves such lateral column aliases, which keeps the statement to one
`SELECT`. If the dry run rejects it, build the array in a subquery in the `FROM` clause
and derive the flag outside it. The contract fixes the resulting columns, not the form.

## `tb_quarentena.sql`

| Element | Contract |
|---|---|
| Statement | `CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_quarentena` |
| Column list | one clause: `CONSTRAINT regra_violada_registrada EXPECT (size(regras_violadas) > 0)`, without `ON VIOLATION` |
| Description | a `COMMENT` in Portuguese |
| Property | `TBLPROPERTIES ("quality" = "silver")` |
| Select list | `* EXCEPT (fl_registro_invalido, data_carga)`, then `current_timestamp() AS data_carga` |
| Source | `FROM STREAM(workspace.silver.temp_tb_validacao_api) WHERE fl_registro_invalido` |

## What a statement must not contain

| Forbidden | Why |
|---|---|
| `ON VIOLATION DROP ROW` or `FAIL UPDATE` on any rule | rules only measure; the split is done by the flag (FR-005) |
| `PARTITIONED BY` | constitution, Principle V; owner's decision (FR-008) |
| `CAST`, renames, or `EXCEPT` of a bronze column | the original record is preserved (FR-002, FR-010) |
| `DISTINCT`, `GROUP BY`, joins, a `WHERE` in the validation table | validation removes nothing (FR-002) |
| a temporary view between bronze and validation | it would drop nothing useful and add a node (research, Decision 1) |
| `CREATE FLOW` | single source per table |
| `LIVE`, `CREATE OR REPLACE`, `APPLY CHANGES` | legacy or non-pipeline syntax (Principle II) |
| a catalog other than `workspace`, or an unqualified table name | constitution, catalog constraint |
| a rule written differently in the `CONSTRAINT` clause and in `regras_violadas` | Principle IV: the flag and the expectations encode the same predicates |

## What consumers may rely on

Conformed silver tables built from API events in later features:

- MUST read `STREAM(workspace.silver.temp_tb_validacao_api)` with
  `WHERE NOT fl_registro_invalido`, and nothing else from this source.
- May rely on `fl_registro_invalido` never being `NULL`, on `origem = 'API'`, and on every
  bronze column being present unchanged.
- MUST NOT restate the rules: the flag is the decision.

Anyone inspecting rejected data:

- May query `workspace.silver.tb_quarentena`. Each row is one bronze event, unchanged,
  with `regras_violadas` naming at least one of `curso_invalido`, `valor_invalido`,
  `forma_pagamento_invalido`, `registro_nao_conforme`.
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
| FR-001, FR-002 | validation statement and source; forbidden list |
| FR-003, FR-006, FR-007 | `regras_violadas` and the flag derived from it |
| FR-004, FR-005 | the four `CONSTRAINT` clauses |
| FR-008 | layout row |
| FR-009, FR-010, FR-011 | quarantine statement |
| FR-012 | `origem` and `data_carga` in both select lists |
| FR-013 | reconciliation in [../quickstart.md](../quickstart.md) |
| FR-014 | "what consumers may rely on" |
| FR-015 | streaming tables over `STREAM(...)` |
| FR-016 | property rows |
| FR-017 | files table |
| FR-018 | documentation tasks (see plan) |
