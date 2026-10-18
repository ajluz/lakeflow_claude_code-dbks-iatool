# Data Model: Silver Access Table from API Events

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18 (revised for constitution v1.8.0)

```text
workspace.silver.temp_tb_validacao_api        (feature 004, private)
        │  STREAM, WHERE NOT fl_registro_invalido
        ▼
workspace.silver.tb_acesso                    (STREAMING TABLE, 4 expectations, keys computed inline)
        ├── kept rows                         2,516,192 on 2026-10-18
        └── dropped by check_endereco_ip_acesso  25,523 (declared exclusion, not quarantined)
```

This is the edge `temp_tb_validacao_api → tb_acesso` of `doc/lakeflow_architecture.png`.
The first version routed it through a shared view, `vw_silver_eventos_api`. That view was
removed when the constitution moved to v1.8.0 ("one expression per key", graph follows the
diagram).

## `workspace.silver.tb_acesso`

One row per valid API access with a usable address. Conformed silver table, published.

| Column | Type | Derivation | Rule |
|---|---|---|---|
| `timestamp_acesso` | TIMESTAMP | `try_to_timestamp(access_date)` | `check_timestamp_acesso`: not null (warn) |
| `endereco_ip_acesso` | STRING | `ip_address` | `check_endereco_ip_acesso`: null or not `'999.999.999.999'` (drop row) |
| `local_acesso` | STRING | `iphone`/`android` → `Mobile`; `chrome`/`safari`/`firefox` → `Computador`; anything else, null included → `unknown` (case-insensitive) | `check_local_acesso`: not `'unknown'` (warn; `FAIL UPDATE` variant commented) |
| `acesso_uuid` | STRING | `md5(concat_ws('\|\|', coalesce(cast(timestamp_acesso AS STRING), ''), coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, '')))` | `check_acesso_uuid`: not null (warn); unique in the table |
| `usuario_uuid` | STRING | `md5(concat_ws('\|\|', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome))` when the event has a user; otherwise null. **The same expression as in `tb_usuario`** | joins `tb_usuario` |
| `curso_uuid` | STRING | `md5(payload.info_produto.product_name)` when the event has a product; otherwise null | equals the catalog's `curso_uuid` |
| `origem` | STRING | `'API'` | never null |
| `data_carga` | TIMESTAMP | `current_timestamp()` | never null |

Exactly these 8 columns, in this order (FR-002).

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-001, FR-015 |
| Source | `STREAM(workspace.silver.temp_tb_validacao_api) WHERE NOT fl_registro_invalido` | FR-001 |
| Hash key | `acesso_uuid`; business key: `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso` | FR-003, FR-010 |
| References | `usuario_uuid` (user; same expression as `tb_usuario`), `curso_uuid` (course; joins `tb_curso` and `dim_curso`) | FR-004, FR-005 |
| `quality` | `silver` | FR-012 |

## Reconciliation

```text
rows(temp_tb_validacao_api WHERE NOT fl_registro_invalido)
  = rows(tb_acesso) + failed(check_endereco_ip_acesso)
  = 2,516,192 + 25,523 = 2,541,715   (2026-10-18)
```

`check_endereco_ip_acesso` is a declared reconciliation exclusion of the API source
(Principle IV, v1.7.0), listed in `doc/pipeline-reference.md`. Expectations count every
incoming row, including rows that another rule drops (implementation finding).

## State of a row

Rows are only appended and never re-evaluated (FR-013). Changing a rule or a derivation
requires a refresh of `tb_acesso`, with the owner's approval.
