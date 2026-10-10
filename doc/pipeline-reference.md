# Pipeline reference

Every dataset defined under [code_tips/](../code_tips/), in dependency order.
Tables carry a `quality` table property (`bronze`, `silver` or `gold`).

## Bronze

All three are streaming tables fed by Auto Loader with
`cloudFiles.inferColumnTypes = true`. Each adds `processing_time`
(`current_timestamp()`) and `source_file_name` (`_metadata.file_path`) to the
source columns, and inherits Auto Loader's `_rescued_data` column.

| Table | File | Reads | Format |
|---|---|---|---|
| `workspace.bronze.dados_database` | [01_bronze_dados_database.sql](../code_tips/01_bronze/01_bronze_dados_database.sql) | `/Volumes/workspace/bronze/landing/database/` | CSV, header, `,` |
| `workspace.bronze.dados_files` | [02_bronze_dados_files.sql](../code_tips/01_bronze/02_bronze_dados_files.sql) | `/Volumes/workspace/bronze/landing/files/` | CSV, header, `,` |
| `workspace.bronze.dados_api` | [03_bronze_dados_api.sql](../code_tips/01_bronze/03_bronze_dados_api.sql) | `/Volumes/workspace/bronze/landing/stream/` | JSON |

Source columns:

- **dados_database** — `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso`, `change_type`, `timestamp_change`
- **dados_files** — `data_venda`, `nome_empresa`, `sexo`, `nome_funcionario`, `email_funcionario`, `profissao`, `idade`, `estado`, `curso`, `valor`, `disconto`
- **dados_api** — `access_date`, `ip_address`, `access_point`, `payload` (struct of `info_usuario`, `info_produto`, `info_pagamento`, each nullable)

## Silver

### Temporary views

Exist only during a pipeline update and are not published to the catalog.

| View | File | Definition |
|---|---|---|
| `vw_bronze_dados_api` | [01](../code_tips/02_silver/01_vw_bronze_dados_api.sql) | `bronze.dados_api` minus `source_file_name`, `_rescued_data` |
| `vw_bronze_dados_files` | [02](../code_tips/02_silver/02_vw_bronze_dados_files.sql) | `bronze.dados_files` minus `source_file_name`, `_rescued_data` |
| `vw_silver_tb_venda_api` | [07](../code_tips/02_silver/07_vw_silver_tb_venda_api.sql) | Sales shaped from valid API events that have a payment payload |
| `vw_silver_tb_venda_files` | [08](../code_tips/02_silver/08_vw_silver_tb_venda_files.sql) | Sales shaped from partner files |
| `vw_bronze_tb_curso` | [10](../code_tips/02_silver/10_vw_bronze_tb_curso.sql) | `bronze.dados_database` plus `origem = 'DATABASE'` |

### temp_tb_validacao_api

[03_temp_tb_validacao_api.sql](../code_tips/02_silver/03_temp_tb_validacao_api.sql)
— temporary streaming table, partitioned by `fl_registro_invalido`.

Reads `vw_bronze_dados_api` and adds `fl_registro_invalido`, which is `TRUE` when
any of these holds:

- `payload.info_produto.product_name = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'`
- `payload.info_pagamento.forma_pagamento = '-----'`
- `payload.info_pagamento.valor = '0.00'`

The same three rules are declared as expectations with no `ON VIOLATION` clause,
so violating rows are kept and only counted in the pipeline's data quality
metrics:

| Expectation | Passes when |
|---|---|
| `curso_invalido` | product name is null or not the placeholder |
| `valor_invalido` | payment value is null or not `'0.00'` |
| `forma_pagamento_invalido` | payment method is null or not `'-----'` |

Downstream tables split on the flag: `TRUE` goes to quarantine, `FALSE` to the
conformed tables.

### tb_quarentena

[04_tb_quarentena.sql](../code_tips/02_silver/04_tb_quarentena.sql) — streaming
table. All rows of the validation table where `fl_registro_invalido = TRUE`, kept
unchanged for later analysis.

### tb_acesso

[05_tb_acesso.sql](../code_tips/02_silver/05_tb_acesso.sql) — streaming table.
One row per valid API access event.

| Column | Derivation |
|---|---|
| `timestamp_acesso` | `access_date` as timestamp |
| `endereco_ip_acesso` | `ip_address` |
| `local_acesso` | `Mobile` for iphone/android, `Computador` for chrome/safari/firefox, otherwise `unknown` |
| `acesso_uuid` | `md5(timestamp_acesso ‖ ip_address ‖ local_acesso)` |
| `usuario_uuid` | `md5(timestamp_acesso ‖ payload.info_usuario.nome)` — null when there is no user payload |
| `curso_uuid` | `md5(payload.info_produto.product_name)` |
| `origem` | `'API'` |
| `data_carga` | load timestamp |

| Expectation | Rule | On violation |
|---|---|---|
| `check_endereco_ip_acesso` | `endereco_ip_acesso != '999.999.999.999'` | drop row |
| `check_local_acesso` | `local_acesso != 'unknown'` | record only (`FAIL UPDATE` is commented out) |

### tb_usuario

[06_tb_usuario.sql](../code_tips/02_silver/06_tb_usuario.sql) — streaming table.
Users from both channels, combined with `UNION ALL`.

| Column | From API | From files |
|---|---|---|
| `usuario_uuid` | `md5(access_date ‖ nome)` | `md5(nome_empresa ‖ nome_funcionario)` |
| `nome_usuario` | `payload.info_usuario.nome` | `nome_funcionario` |
| `email_usuario` | `payload.info_usuario.email` | `email_funcionario` |
| `idade_usuario` | `idade` as int | `idade` as int |
| `sexo_usuario` | `payload.info_usuario.sexo` | `sexo` |
| `estado_usuario` | `payload.info_usuario.estado` | `estado` |
| `profissao_usuario` | `payload.info_usuario.profissao` | `profissao` |
| `empresa_usuario` | null | `nome_empresa` |
| `origem` | `'API'` | `'ARQUIVO'` |
| `data_carga` | load timestamp | load timestamp |

The API branch keeps only valid events that carry a user payload.

| Expectation | Rule | On violation |
|---|---|---|
| `check_sexo_usuario` | `sexo_usuario IN ('M', 'F')` | drop row |
| `check_email_usuario` | `email_usuario LIKE '%@%'` | record only |

### tb_venda

[09_tb_venda.sql](../code_tips/02_silver/09_tb_venda.sql) — streaming table
declared empty and filled by two append flows, one per source view:

- `silver_tb_venda_api_flow` ← `vw_silver_tb_venda_api`
- `silver_tb_venda_files_flow` ← `vw_silver_tb_venda_files`

| Column | From API | From files |
|---|---|---|
| `data_venda` | `access_date` as timestamp | `data_venda` as timestamp |
| `acesso_uuid` | hash of access attributes | null |
| `usuario_uuid` | `md5(access_date ‖ nome)` | `md5(nome_empresa ‖ nome_funcionario)` |
| `curso_uuid` | `md5(product_name)` | `md5(curso)` |
| `forma_pagamento` | `payload.info_pagamento.forma_pagamento` | `'pix'` |
| `quantidade_parcelas` | from payload | `1` |
| `valor_parcelas` | from payload | list price minus discount |
| `valor_pago` | `quantidade_parcelas × valor_parcelas` | list price minus discount |
| `percentual_disconto` | discount as `'5%'`-style text, null when none | `disconto` as received |
| `valor_desconto` | list price × discount | list price × discount |
| `origem` | `'API'` | `'ARQUIVO'` |
| `data_carga` | load timestamp | load timestamp |

List prices arrive as text such as `R$ 247,00` and are parsed with
`substr(..., 4)` plus a comma-to-dot replacement.

### tb_curso

[11_tb_curso.sql](../code_tips/02_silver/11_tb_curso.sql) — streaming table,
target of an `AUTO CDC` flow (`silver_tb_curso_flow`) stored as **SCD type 1**.

| Setting | Value |
|---|---|
| Source | `vw_bronze_tb_curso` |
| Key | `curso_uuid` |
| Sequence | `timestamp_change` |
| Delete condition | `change_type = "delete"` |
| Columns excluded | `timestamp_change`, `change_type`, `_rescued_data`, `processing_time`, `source_file_name` |

Resulting columns: `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso`,
`origem`. The table always holds the latest version of each course.

## Gold

### dim_tempo (outside the pipeline)

Calendar dimension created by the last cell of
[functions.py](../explorations/functions.py), one row per day from 2024-06-01 to
2026-12-31. Columns: `sk_tempo`, `data`, `ano`, `mes` (Portuguese month name),
`mes_ano` (month number), `dia_semana_int`, `dia_semana` (Portuguese day name),
`fl_dia_semana` (true Monday–Friday), `dia_mes`, `fl_ultimo_dia_mes`, `dia_ano`,
`semana_ano`, `bimestre`, `trimestre`, `semestre`, `data_carga`.

### dim_usuario

[01_dim_usuario.sql](../code_tips/03_gold/01_dim_usuario.sql) — materialized
view over `silver.tb_usuario` (all columns except `data_carga`), with identity
surrogate key `sk_usuario` and `dt_carga` defaulting to the load time.

### dim_curso

[02_dim_curso.sql](../code_tips/03_gold/02_dim_curso.sql) — streaming table,
target of an `AUTO CDC` flow (`gold_dim_curso_flow`) stored as **SCD type 2**.
Same key, sequence, delete condition and excluded columns as `tb_curso`, but it
reads `bronze.dados_database` directly.

Columns: `sk_curso` (identity), `curso_uuid`, `nome_curso`, `nivel_curso`,
`valor_curso`, `__START_AT`, `__END_AT`. The current version of a course is the
row where `__END_AT IS NULL`.

### dim_codigos

[03_dim_codigos.sql](../code_tips/03_gold/03_dim_codigos.sql) — materialized
view. A junk dimension holding the distinct combinations of low-cardinality sale
attributes.

Columns: `sk_codigos` (identity), `origem_usuario`, `local_acesso`
(`'Não se aplica'` for file sales), `forma_pagamento`, `percentual_disconto`
(`'Não se aplica'` when null), `data_carga`.

Built from `SELECT DISTINCT` over `silver.tb_venda CROSS JOIN silver.tb_acesso`.

### fato_venda

[04_fato_vendas.sql](../code_tips/03_gold/04_fato_vendas.sql) — materialized
view. Sales fact at one row per sale.

| Column | Resolved by |
|---|---|
| `sk_tempo` | `dim_tempo.data = CAST(data_venda AS DATE)` |
| `sk_codigos` | match on payment method, origin, access location and discount percentage |
| `sk_curso` | `curso_uuid`, current version only (`__END_AT IS NULL`) |
| `sk_usuario` | `usuario_uuid` |
| `valor_desconto` | measure |
| `valor_pago` | measure |

Sales are first joined to `silver.tb_acesso` on `acesso_uuid` to pick up the
access location. All joins are inner joins.

### obt_acesso

[05_obt_acesso.sql](../code_tips/03_gold/05_obt_acesso.sql) — materialized view.
One row per access event, denormalized with every `dim_tempo` attribute, for
funnel analysis without joins.

| Column | Meaning |
|---|---|
| `local_acesso`, `endereco_ip_acesso` | access attributes |
| `data`, `ano`, `mes`, … | calendar attributes |
| `qtde_acesso` | always 1 |
| `qtde_usuario` | 1 when the access has an identified user |
| `qtde_vendidos` | 1 when the access resulted in a sale (left join to `tb_venda`) |
