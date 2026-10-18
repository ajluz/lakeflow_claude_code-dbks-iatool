# Data Model: Silver Access Table from API Events

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

```text
workspace.silver.temp_tb_validacao_api        (feature 004, private)
        │  STREAM, WHERE NOT fl_registro_invalido
        ▼
vw_silver_eventos_api                         (TEMPORARY VIEW: valid API events + shared keys)
        │  STREAM
        ▼
workspace.silver.tb_acesso                    (STREAMING TABLE, 4 expectations)
        ├── kept rows                         2,516,192 on 2026-10-18
        └── dropped by check_endereco_ip_acesso  25,523 (declared exclusion, not quarantined)
```

## `vw_silver_eventos_api` (shared view of valid API events)

Pipeline-scoped temporary view, streaming, not persisted. It is the single place where
the API source's reference keys are defined (Principle VI).

| Column | Type | Derivation |
|---|---|---|
| every column of `temp_tb_validacao_api` | as there | unchanged (`processing_time`, `access_date`, `access_point`, `ip_address`, `payload`, `regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga`) |
| `timestamp_acesso` | TIMESTAMP | `try_to_timestamp(access_date)` |
| `usuario_uuid` | STRING | `md5(concat_ws('\|\|', coalesce(cast(timestamp_acesso AS STRING), ''), payload.info_usuario.nome))` when `payload.info_usuario.nome` is not null; otherwise null |
| `curso_uuid` | STRING | `md5(payload.info_produto.product_name)` when the product name is not null; otherwise null |

Rows: exactly the validation rows with `fl_registro_invalido = false` (2,541,715 on
2026-10-18). No filter, rule or cast beyond these derivations.

## `workspace.silver.tb_acesso`

One row per valid API access with a usable address. Conformed silver table, published.

| Column | Type | Derivation | Rule |
|---|---|---|---|
| `timestamp_acesso` | TIMESTAMP | from the view | `check_timestamp_acesso`: not null (warn) |
| `endereco_ip_acesso` | STRING | `ip_address` | `check_endereco_ip_acesso`: null or not `'999.999.999.999'` (drop row) |
| `local_acesso` | STRING | `iphone`/`android` → `Mobile`; `chrome`/`safari`/`firefox` → `Computador`; anything else, null included → `unknown` (case-insensitive) | `check_local_acesso`: not `'unknown'` (warn; `FAIL UPDATE` variant commented) |
| `acesso_uuid` | STRING | `md5(concat_ws('\|\|', coalesce(cast(timestamp_acesso AS STRING), ''), coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, '')))` | `check_acesso_uuid`: not null (warn); unique in the table |
| `usuario_uuid` | STRING | from the view | null when the event has no user |
| `curso_uuid` | STRING | from the view | null when the event has no product; equals the catalog's `curso_uuid` |
| `origem` | STRING | `'API'` | never null |
| `data_carga` | TIMESTAMP | `current_timestamp()` | never null |

Exactly these 8 columns, in this order (FR-002). No other column of the view is carried.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-001, FR-015 |
| Hash key | `acesso_uuid`; business key: `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso` | FR-003, FR-010 |
| References | `usuario_uuid` (user), `curso_uuid` (course, joins `tb_curso` and `dim_curso`) | FR-004, FR-005 |
| `quality` | `silver` | FR-012 |
| Layout | none | Principle V |

## Reconciliation

```text
rows(temp_tb_validacao_api WHERE NOT fl_registro_invalido)
  = rows(tb_acesso) + failed(check_endereco_ip_acesso)
  = 2,516,192 + 25,523 = 2,541,715   (2026-10-18)
```

`check_endereco_ip_acesso` is a declared reconciliation exclusion of the API source
(Principle IV, v1.7.0). It is listed in `doc/pipeline-reference.md`.

## State of a row

Rows are only appended. A row once loaded is not re-evaluated (FR-013). Changing a rule
or a derivation requires a refresh of `tb_acesso`, which needs the owner's approval.
