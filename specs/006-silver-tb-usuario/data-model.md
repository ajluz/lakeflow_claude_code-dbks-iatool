# Data Model: Silver User Table from API Events and Partner Files

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

```text
vw_silver_eventos_api (feature 005)              workspace.bronze.dados_files
        │ STREAM, usuario_uuid IS NOT NULL                │ STREAM
        │                                                 ▼
        │                                     vw_bronze_dados_files      (boundary: drops source_file_name, _rescued_data)
        │                                                 │
        │                                                 ▼
        │                                     vw_silver_vendas_arquivo   (shared: + usuario_uuid of the files source)
        ▼                                                 ▼
vw_silver_usuario_api                         vw_silver_usuario_arquivo  (target shape)
        │ append (silver_tb_usuario_api_flow)              │ append (silver_tb_usuario_arquivo_flow)
        └──────────────────────► workspace.silver.tb_usuario ◄─────────┘
                                 streaming table, 3 expectations
```

## Views

| View | Reads | Adds / shapes |
|---|---|---|
| `vw_bronze_dados_files` | `STREAM(workspace.bronze.dados_files)` | `* EXCEPT (source_file_name, _rescued_data)`; nothing else |
| `vw_silver_vendas_arquivo` | `STREAM(vw_bronze_dados_files)` | every column, plus `usuario_uuid = md5(concat_ws('\|\|', coalesce(nome_empresa, ''), coalesce(nome_funcionario, '')))`, the single definition of the files user key |
| `vw_silver_usuario_api` | `STREAM(vw_silver_eventos_api)` with `WHERE usuario_uuid IS NOT NULL` | the 10 target columns from the API |
| `vw_silver_usuario_arquivo` | `STREAM(vw_silver_vendas_arquivo)` | the 10 target columns from the files |

All four are streaming temporary views, not persisted.

## `workspace.silver.tb_usuario`

One row per user key. Conformed silver table, published.

| Column | Type | API | Files | Rule |
|---|---|---|---|---|
| `usuario_uuid` | STRING | from `vw_silver_eventos_api` (time + name) | from `vw_silver_vendas_arquivo` (company + name) | `check_usuario_uuid`: not null (warn); unique (verified after each load) |
| `nome_usuario` | STRING | `payload.info_usuario.nome` | `nome_funcionario` | — |
| `email_usuario` | STRING | `payload.info_usuario.email` | `email_funcionario` | `check_email_usuario`: not null and contains `@` (warn) |
| `idade_usuario` | INT | `try_cast(payload.info_usuario.idade AS INT)` | `try_cast(idade AS INT)` | null when not a whole number |
| `sexo_usuario` | STRING | `payload.info_usuario.sexo` | `sexo` | `check_sexo_usuario`: not null and in (`M`, `F`) (drop row) |
| `estado_usuario` | STRING | `payload.info_usuario.estado` | `estado` | — |
| `profissao_usuario` | STRING | `payload.info_usuario.profissao` | `profissao` | — |
| `empresa_usuario` | STRING | null | `nome_empresa` | filled exactly on `ARQUIVO` rows |
| `origem` | STRING | `'API'` | `'ARQUIVO'` | never null |
| `data_carga` | TIMESTAMP | `current_timestamp()` | `current_timestamp()` | never null |

Exactly these 10 columns, in this order.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-001 |
| Flows | `silver_tb_usuario_api_flow`, `silver_tb_usuario_arquivo_flow`, both `INSERT INTO ... BY NAME` | FR-005 |
| Uniqueness | `usuario_uuid` unique: each key occurs once in today's data; verified after each load, not enforced | FR-007 |
| `quality` | `silver` | FR-012 |
| Hash key business columns | API: `timestamp_acesso`, `payload.info_usuario.nome`. Files: `nome_empresa`, `nome_funcionario` | FR-015 |

## Expected counts (2026-10-18)

```text
API:   756,249 candidate users − 15,015 (sexo X) = 741,234 rows
Files: 200,000 candidate users − 0               = 200,000 rows
tb_usuario                                        = 941,234 rows
check_sexo_usuario failed  = 15,015   (declared exclusion, not quarantined)
check_email_usuario failed = 30,190   (all candidate API rows; files 0)
```

## State of a row

Rows are only appended. A delivery whose sex fails the rule is dropped. A re-delivered
key would be appended as a second row, and the uniqueness check would report it. Nothing
updates or deletes a row. Changing a rule or a derivation requires a refresh of `tb_usuario`, which
needs the owner's approval.
