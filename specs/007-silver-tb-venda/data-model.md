# Data Model: Silver Sales Table from API Events and Partner Files

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

```text
workspace.silver.temp_tb_validacao_api              vw_bronze_dados_files   (feature 006 boundary view)
        │ STREAM, NOT fl_registro_invalido                  │ STREAM
        │        AND payload.info_pagamento IS NOT NULL     │
        ▼                                                   ▼
vw_silver_tb_venda_api   (V3)                        vw_silver_tb_venda_files   (V4)
        │ append (silver_tb_venda_api_flow)                 │ append (silver_tb_venda_files_flow)
        └──────────────────► workspace.silver.tb_venda ◄────┘   (S4)
                             streaming table, 5 warn expectations
```

These are the edges `T1 → V3 → S4` and `V2 → V4 → S4` of
`doc/lakeflow_architecture.png`.

## `workspace.silver.tb_venda`

Conformed silver table, published. Each flow view shapes its source into these columns
(`09_vw_silver_tb_venda_api.sql`, `10_vw_silver_tb_venda_files.sql`). In the API column,
`timestamp_acesso`, `endereco_ip_acesso` and `local_acesso` are the inner-query aliases
defined exactly as in `05_tb_acesso.sql`. `<preco>` is the list price and `<fracao>` the
discount fraction (below).

| Column | Type | API flow | Files flow | Rule |
|---|---|---|---|---|
| `venda_uuid` | STRING | `md5(concat_ws('\|\|', coalesce(cast(timestamp_acesso AS STRING), ''), coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, ''), coalesce(payload.info_produto.product_name, ''), coalesce(payload.info_usuario.nome, '')))` (user name added 2026-10-28, research Decision 4) | `md5(concat_ws('\|\|', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''), coalesce(cast(data_venda AS STRING), ''), coalesce(curso, '')))` | `check_venda_uuid`: not null; unique (verified after each load) |
| `data_venda` | TIMESTAMP | `timestamp_acesso` | `CAST(data_venda AS TIMESTAMP)` | `check_data_venda`: not null |
| `acesso_uuid` | STRING | `05_tb_acesso.sql`'s expression, same text | `CAST(NULL AS STRING)` | empty exactly on `ARQUIVO` rows |
| `usuario_uuid` | STRING | `05_tb_acesso.sql`'s expression, same text | `07_vw_silver_tb_usuario_files.sql`'s expression, same text | `check_usuario_uuid`: not null |
| `curso_uuid` | STRING | `05_tb_acesso.sql`'s expression, same text | `md5(curso)` | `check_curso_uuid`: not null |
| `forma_pagamento` | STRING | `payload.info_pagamento.forma_pagamento` | `'pix'` | — |
| `quantidade_parcelas` | INT | `try_cast(payload.info_pagamento.quantidade_parcelas AS INT)` | `1` | — |
| `valor_parcelas` | DECIMAL(9,2) | `CAST(payload.info_pagamento.valor_parcelas AS DECIMAL(9,2))` | `CAST(<preco> - valor_desconto AS DECIMAL(9,2))` | — |
| `valor_pago` | DECIMAL(9,2) | `CAST(quantidade_parcelas * valor_parcelas AS DECIMAL(9,2))` | same | `check_valor_pago`: not null and > 0 |
| `percentual_desconto` | STRING | `concat(CAST(<fracao> * 100 AS INT), '%')` | `coalesce(disconto, '0%')` | in {`0%`, `5%`, `10%`, `15%`} (verified) |
| `valor_desconto` | DECIMAL(9,2) | `CAST(<preco> * <fracao> AS DECIMAL(9,2))` | same | `0.00` when no discount |
| `origem` | STRING | `'API'` | `'ARQUIVO'` | never null |
| `data_carga` | TIMESTAMP | `current_timestamp()` | `current_timestamp()` | never null |

Exactly these 13 columns, in this order.

| Helper | API | Files |
|---|---|---|
| `<preco>` | `try_cast(replace(regexp_replace(payload.info_produto.valor, '[^0-9,]', ''), ',', '.') AS DECIMAL(9,2))` | the same over `valor` |
| `<fracao>` | `CAST(coalesce(payload.info_pagamento.disconto, 0) AS DECIMAL(5,2))` | `CAST(CAST(replace(coalesce(disconto, '0%'), '%', '') AS DECIMAL(5,2)) / 100 AS DECIMAL(5,2))` |

Helpers and the files columns that later columns reuse (`valor_desconto` in
`valor_parcelas`) are lateral column aliases or inner-query columns. They are not
selected into the table.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, append-only | FR-001 |
| Flows | `silver_tb_venda_api_flow` from `vw_silver_tb_venda_api`, `silver_tb_venda_files_flow` from `vw_silver_tb_venda_files`, both `INSERT INTO ... BY NAME SELECT * FROM STREAM(<view>)` | FR-010 |
| Uniqueness | `venda_uuid` unique: verified after each load, not enforced | FR-006 |
| `quality` | `silver` | FR-012 |
| Hash key business columns | API: access time, address, access location, `product_name`, user name. Files: `nome_empresa`, `nome_funcionario`, `data_venda`, `curso` | FR-006, FR-015 |

## Relationships

| Column | Joins | Expected unmatched |
|---|---|---|
| `acesso_uuid` (API) | `tb_acesso.acesso_uuid` | sales whose event had the address `999.999.999.999`, which `tb_acesso` drops |
| `usuario_uuid` | `tb_usuario.usuario_uuid` | sales whose user's sex is not `M` or `F`, which `tb_usuario` drops |
| `curso_uuid` | the catalog's `curso_uuid` (`md5(nome_curso)`), three values | none |

Unmatched rows are kept and counted (spec SC-004, SC-005). Gold will resolve them to an
"unknown" member (Principle VII).

## Expected counts

```text
API:   valid events with a payment            220,472 (2026-10-28)
Files: rows of workspace.bronze.dados_files    200,000
tb_venda = API + files                          420,472; no rule drops a row
Every expectation: 0 failed
```

## State of a row

Rows are only appended. A re-delivered sale would be appended as a second row, and the
uniqueness check would report it.
