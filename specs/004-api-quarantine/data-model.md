# Data Model: Validation and Quarantine of API Events

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

Two streaming tables in `workspace.silver`, fed in sequence from the bronze API events.

```text
workspace.bronze.dados_api
        │  STREAM, every row
        ▼
workspace.silver.temp_tb_validacao_api   (PRIVATE, CLUSTER BY fl_registro_invalido)
        │                                   4 warn expectations
        ├── fl_registro_invalido = true  ──▶ workspace.silver.tb_quarentena
        └── fl_registro_invalido = false ──▶ conformed silver tables (later features)
```

## `workspace.silver.temp_tb_validacao_api`

Every bronze API event, unchanged, plus the result of validation. Private to the
pipeline, so it is not in the catalog.

| Column | Type | Origin | Rule |
|---|---|---|---|
| `processing_time` | TIMESTAMP | bronze | unchanged |
| `source_file_name` | STRING | bronze | unchanged |
| `access_date` | STRING | bronze | unchanged |
| `access_point` | STRING | bronze | unchanged |
| `ip_address` | STRING | bronze | unchanged |
| `payload` | STRUCT | bronze | unchanged, nesting preserved |
| `_rescued_data` | STRING | bronze | unchanged |
| `regras_violadas` | ARRAY&lt;STRING&gt; | derived | names of the rules the event failed, in the order of the table below; empty array when none failed; never `NULL` (FR-007) |
| `fl_registro_invalido` | BOOLEAN | `size(regras_violadas) > 0` | true when at least one rule failed; never `NULL` (FR-003, FR-006) |
| `origem` | STRING | literal `'API'` | never `NULL`; not derived from the data (FR-012) |
| `data_carga` | TIMESTAMP | `current_timestamp()` | when the row was validated; never `NULL` (FR-012) |

The bronze columns come through `*`, so a column added to the source later reaches this
table without a code change. Their order and types are those of bronze.

| Property | Value | Requirement |
|---|---|---|
| Kind | private streaming table, append-only | FR-001 |
| Physical layout | `CLUSTER BY (fl_registro_invalido)`; never `PARTITIONED BY` | FR-008 |
| `quality` | `silver` | FR-016 |
| Row count | equals bronze, for every update | FR-002, FR-013 |

### Validation rules

Declared as `CONSTRAINT <name> EXPECT (<condition>)` with no `ON VIOLATION` clause (warn
only, FR-005). A rule passes when its condition is true. No condition can return `NULL`.

| Order | Name | Condition | Empty field |
|---|---|---|---|
| 1 | `curso_invalido` | `payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` | passes |
| 2 | `valor_invalido` | `payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00'` | passes |
| 3 | `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----'` | passes |
| 4 | `registro_nao_conforme` | `_rescued_data IS NULL` | passes (nothing rescued) |

The placeholder in rule 1 is exactly 32 lowercase `x`. Rule 2's comparison follows the
column's type ([research.md](research.md), Decision 4).

**Invariant** (FR-006): for every row, `fl_registro_invalido` is true if and only if at
least one of the four conditions is false, and `regras_violadas` holds exactly the names of
the false ones.

## `workspace.silver.tb_quarentena`

The rejected events, unchanged, with the reasons. Published to the catalog.

| Column | Type | Origin | Rule |
|---|---|---|---|
| `processing_time` … `_rescued_data` | as bronze | validation table | every bronze column, same name, type and value (FR-010) |
| `regras_violadas` | ARRAY&lt;STRING&gt; | validation table | at least one name (FR-011) |
| `origem` | STRING | validation table | `'API'` (FR-012) |
| `data_carga` | TIMESTAMP | `current_timestamp()` | when the row entered quarantine; replaces the validation table's value (FR-012) |

`fl_registro_invalido` is not carried: it is true on every row.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-009 |
| Rows | exactly the validation rows where `fl_registro_invalido` is true | FR-009 |
| Expectation | `regra_violada_registrada`: `size(regras_violadas) > 0`, warn only | Principle III, FR-011 |
| `quality` | `silver` | FR-016 |
| Hash key | none: not a conformed table (Principle VI applies to conformed tables) | research, Decision 6 |

## Reconciliation

For every update, and in total (FR-013, SC-004):

```text
rows(bronze.dados_api) = rows(temp_tb_validacao_api)
                       = rows(flag false) + rows(tb_quarentena)
```

No exclusion is documented for this source.

## State of a row

A row has no lifecycle beyond its first classification: once validated, it is not
re-evaluated (FR-015). A quarantined row stays in quarantine. Reprocessing after a fix is
out of scope. Re-evaluating old rows under changed rules requires a full refresh, which
needs the owner's approval.
