# Data Model: Silver User Table from API Events and Partner Files

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18 (revised for constitution v1.8.0)

```text
workspace.silver.temp_tb_validacao_api       workspace.bronze.dados_files
        │ STREAM, NOT fl_registro_invalido            │ STREAM
        │        AND payload.info_usuario.nome        ▼
        │            IS NOT NULL               vw_bronze_dados_files   (boundary: drops source_file_name, _rescued_data)
        │                                             │
        ▼                                             ▼
vw_silver_tb_usuario_api                       vw_silver_tb_usuario_files   (flow views: the 10 columns)
        │ append (silver_tb_usuario_api_flow)         │ append (silver_tb_usuario_files_flow)
        └──────────────► workspace.silver.tb_usuario ◄┘
                         streaming table, 3 expectations
```

These are the edges `temp_tb_validacao_api → tb_usuario` and
`vw_bronze_dados_files → tb_usuario` of `doc/lakeflow_architecture.png`. The first versions
had four more views (`vw_silver_eventos_api`, `vw_silver_vendas_arquivo`,
`vw_silver_usuario_api`, `vw_silver_usuario_arquivo`). They were removed under constitution
v1.8.0.

## `vw_bronze_dados_files` (boundary view)

`src/pipeline/02_silver/02_vw_bronze_dados_files.sql`:
`SELECT * EXCEPT (source_file_name, _rescued_data) FROM STREAM(workspace.bronze.dados_files)`.
Nothing else.

## `workspace.silver.tb_usuario`

Conformed silver table, published. Each flow view shapes its source into these columns (`06_vw_silver_tb_usuario_api.sql`, `07_vw_silver_tb_usuario_files.sql`).

| Column | Type | API flow | Files flow | Rule |
|---|---|---|---|---|
| `usuario_uuid` | STRING | `md5(concat_ws('\|\|', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome))`, **the same expression as `tb_acesso`** | `md5(concat_ws('\|\|', coalesce(nome_empresa, ''), coalesce(nome_funcionario, '')))` | `check_usuario_uuid`: not null (warn); unique (verified after each load) |
| `nome_usuario` | STRING | `payload.info_usuario.nome` | `nome_funcionario` | — |
| `email_usuario` | STRING | `payload.info_usuario.email` | `email_funcionario` | `check_email_usuario`: not null and contains `@` (warn) |
| `idade_usuario` | INT | `try_cast(payload.info_usuario.idade AS INT)` | `try_cast(idade AS INT)` | null when not a whole number |
| `sexo_usuario` | STRING | `payload.info_usuario.sexo` | `sexo` | `check_sexo_usuario`: not null and in (`M`, `F`) (drop row) |
| `estado_usuario` | STRING | `payload.info_usuario.estado` | `estado` | — |
| `profissao_usuario` | STRING | `payload.info_usuario.profissao` | `profissao` | — |
| `empresa_usuario` | STRING | `CAST(NULL AS STRING)` | `nome_empresa` | filled exactly on `ARQUIVO` rows |
| `origem` | STRING | `'API'` | `'ARQUIVO'` | never null |
| `data_carga` | TIMESTAMP | `current_timestamp()` | `current_timestamp()` | never null |

Exactly these 10 columns, in this order.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-001 |
| Flows | `silver_tb_usuario_api_flow` from `vw_silver_tb_usuario_api`, `silver_tb_usuario_files_flow` from `vw_silver_tb_usuario_files`, both `INSERT INTO ... BY NAME SELECT * FROM STREAM(<view>)` (constitution v1.9.0) | FR-005, FR-006 |
| Uniqueness | `usuario_uuid` unique: each key occurs once in today's data; verified after each load, not enforced | FR-007 |
| `quality` | `silver` | FR-012 |
| Hash key business columns | API: `access_date` (as timestamp), `payload.info_usuario.nome`. Files: `nome_empresa`, `nome_funcionario` | FR-015 |

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
key would be appended as a second row, and the uniqueness check would report it.
