# Data Model: Bronze Ingestion of the Three Landing Sources

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-11

Three streaming tables in `workspace.bronze`, one per landing source. Source columns and
their types are inferred from the files; the types below are what the inference returned
for the data in the landing volume on 2026-10-11 and are not declared in the code.

## Common to all three tables

| Column | Type | Origin | Rule |
|---|---|---|---|
| `processing_time` | TIMESTAMP | `current_timestamp()` | never null; the moment the row was processed (FR-006) |
| `source_file_name` | STRING | `_metadata.file_path` | never null; full path of the file, in the form `dbfs:/Volumes/workspace/bronze/landing/<folder>/<file>` (FR-007) |
| *source columns* | inferred | the file | every column of the source, under its own name (FR-005) |
| `_rescued_data` | STRING | Auto Loader | null when the record fits the inferred schema; otherwise holds the content that did not fit (FR-008) |

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-003 |
| `quality` | `bronze` | FR-009 |
| Column order | the two lineage columns, then the source columns, then `_rescued_data` | research, Decision 2 |

Rules that hold for all three (FR-010): no row is filtered, no column is cast, renamed or
dropped, no deduplication, and no expectation removes rows or stops the run.

## `workspace.bronze.dados_api`

Site events. Source folder `stream/`, JSON, one object per line.

| Source column | Inferred type | Meaning |
|---|---|---|
| `access_date` | STRING | when the site was accessed |
| `access_point` | STRING | device or browser (`iphone`, `android`, `chrome`, `safari`, `firefox`, `unknown`) |
| `ip_address` | STRING | address the access came from |
| `payload` | STRUCT | nested content, each part optional |
| `payload.info_usuario` | STRUCT | `nome`, `idade`, `sexo`, `email`, `profissao`, `estado` |
| `payload.info_produto` | STRUCT | `product_name`, `valor` |
| `payload.info_pagamento` | STRUCT | `disconto`, `valor`, `forma_pagamento`, `quantidade_parcelas`, `valor_parcelas` |

Nesting is preserved; nested fields are queried by name, for example
`payload.info_produto.product_name`.

## `workspace.bronze.dados_files`

Corporate sales from partner companies. Source folder `files/`, CSV with header.

| Source column | Inferred type | Meaning |
|---|---|---|
| `data_venda` | DATE | sale date |
| `nome_empresa` | STRING | partner company |
| `sexo` | STRING | employee's sex |
| `nome_funcionario` | STRING | employee's name |
| `email_funcionario` | STRING | employee's email |
| `profissao` | STRING | employee's profession |
| `idade` | INT | employee's age |
| `estado` | STRING | state |
| `curso` | STRING | course name |
| `valor` | STRING | list price as text, for example `R$ 247,00` |
| `disconto` | STRING | discount as text, for example `5%` |

## `workspace.bronze.dados_database`

Course catalog change feed. Source folder `database/`, CSV with header.

| Source column | Inferred type | Meaning |
|---|---|---|
| `curso_uuid` | STRING | course key delivered by the source |
| `nome_curso` | STRING | course name |
| `nivel_curso` | STRING | level (`beginner`, `intermediate`, `advanced`) |
| `valor_curso` | DOUBLE | price |
| `change_type` | STRING | `insert`, `update` or `delete` |
| `timestamp_change` | TIMESTAMP | when the change happened |

## Relationships

None in bronze. The three tables are independent; relating a sale to a course or a user
happens in silver. Each table depends only on its landing folder.

```text
landing/stream/    ──▶ bronze.dados_api
landing/files/     ──▶ bronze.dados_files
landing/database/  ──▶ bronze.dados_database
```

## Lifecycle of a source file

```text
 arrives in the folder ──▶ ingested by the next run ──▶ never ingested again
```

- A file is ingested once (FR-011). A later run reads only files that arrived after the
  previous run (FR-012).
- A file rewritten under a new name is a new file and is ingested again. Bronze keeps every
  delivery.
- A full refresh of a table discards what was ingested and reads every file in the folder
  again. It is never part of a normal run and needs the owner's approval.

## Validation rules derived from the requirements

| # | Rule | Check |
|---|---|---|
| V1 | Row count of each table equals the record count of its landing files | SC-002 |
| V2 | `processing_time` and `source_file_name` are never null | SC-003 |
| V3 | The set of `source_file_name` values equals the set of file paths in the landing folder | SC-004 |
| V4 | The table's columns are the source's columns plus `processing_time` and `source_file_name` | SC-005 |
| V5 | A run with no new files adds 0 rows | SC-006 |
| V6 | A new file adds exactly its records to its own table and nothing to the others | SC-007 |
| V7 | The `quality` property is `bronze` | SC-008 |
