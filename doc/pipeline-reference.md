# Pipeline reference

Every dataset of the pipeline, in dependency order. Tables carry a `quality`
table property (`bronze`, `silver` or `gold`).

The Bronze section, and in Silver the view `vw_bronze_dados_api` and the sections
`temp_tb_validacao_api` and `tb_quarentena`, describe the pipeline as it is built
today, under [src/pipeline/](../src/pipeline/). The other Silver datasets and the Gold
section still describe the earlier pipeline, whose `code_tips/` folder is no longer
in the repository; they will be replaced as those layers are rebuilt.

## Bronze

Three streaming tables in `workspace.bronze`, one per source of the landing
volume. Each is loaded incrementally with Auto Loader, written in SQL as
`STREAM read_files(...)`, and holds the source data exactly as it arrived:
nothing is filtered, cast, renamed or deduplicated.

| Table | File | Reads | Format |
|---|---|---|---|
| `workspace.bronze.dados_api` | [01_dados_api.sql](../src/pipeline/01_bronze/01_dados_api.sql) | `/Volumes/workspace/bronze/landing/stream/` | JSON |
| `workspace.bronze.dados_files` | [02_dados_files.sql](../src/pipeline/01_bronze/02_dados_files.sql) | `/Volumes/workspace/bronze/landing/files/` | CSV, header, `,` |
| `workspace.bronze.dados_database` | [03_dados_database.sql](../src/pipeline/01_bronze/03_dados_database.sql) | `/Volumes/workspace/bronze/landing/database/` | CSV, header, `,` |

Every table has the same shape:

| Column | Origin | Notes |
|---|---|---|
| `processing_time` | `current_timestamp()` | when the row was processed; never null |
| `source_file_name` | `_metadata.file_path` | full path of the file the row came from, for example `/Volumes/workspace/bronze/landing/database/part-00000-....csv`; never null |
| source columns | the file | every column of the source, under its own name, with inferred types |
| `_rescued_data` | Auto Loader | null when the record fits the inferred schema; otherwise the content that did not fit |

Each table carries `TBLPROPERTIES ("quality" = "bronze")` and a description.

Source columns, with the types inferred from the current data:

- **dados_api** — `access_date` (string), `access_point` (string), `ip_address` (string), `payload` (struct of `info_usuario`, `info_produto`, `info_pagamento`, each nullable)
- **dados_files** — `data_venda` (date), `nome_empresa`, `sexo`, `nome_funcionario`, `email_funcionario`, `profissao`, `idade` (int), `estado`, `curso`, `valor` (string, `R$ 247,00`), `disconto` (string, `5%`)
- **dados_database** — `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso` (double), `change_type` (`insert`, `update`, `delete`), `timestamp_change` (timestamp)

A file is ingested once. A later run reads only files that arrived since the
previous run; entries whose names start with `_`, such as Spark's marker files,
are skipped. Because column types are inferred, each source folder must hold at
least one data file before the first run.

## Silver

### Temporary views

Exist only during a pipeline update and are not published to the catalog.

| View | File | Definition |
|---|---|---|
| `vw_bronze_dados_api` | [01](../src/pipeline/02_silver/01_vw_bronze_dados_api.sql) | `STREAM(bronze.dados_api)` minus `source_file_name`, `_rescued_data`; the bronze-to-silver boundary of the API source. As built |
| `vw_bronze_dados_files` | [02](../code_tips/02_silver/02_vw_bronze_dados_files.sql) | `bronze.dados_files` minus `source_file_name`, `_rescued_data` |
| `vw_silver_tb_venda_api` | [07](../code_tips/02_silver/07_vw_silver_tb_venda_api.sql) | Sales shaped from valid API events that have a payment payload |
| `vw_silver_tb_venda_files` | [08](../code_tips/02_silver/08_vw_silver_tb_venda_files.sql) | Sales shaped from partner files |
| `vw_bronze_tb_curso` | [10](../code_tips/02_silver/10_vw_bronze_tb_curso.sql) | `bronze.dados_database` plus `origem = 'DATABASE'` |

### temp_tb_validacao_api

[02_temp_tb_validacao_api.sql](../src/pipeline/02_silver/02_temp_tb_validacao_api.sql)
— private streaming table `workspace.silver.temp_tb_validacao_api`, partitioned by
`fl_registro_invalido`. As built.

Reads `STREAM(vw_bronze_dados_api)`, so it never sees `source_file_name` or
`_rescued_data`. It keeps every column of the view unchanged and validates each API
event once, against three rules. A rule passes when its field is empty, so a visit
without a purchase is valid:

| Expectation | Passes when |
|---|---|
| `curso_invalido` | `payload.info_produto.product_name` is null or not `'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` (32 `x`) |
| `valor_invalido` | `payload.info_pagamento.valor` is null or not `0.00` (the column is `DOUBLE`, so every zero amount fails) |
| `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento` is null or not `'-----'` |

The expectations have no `ON VIOLATION` clause: they only count failures in the
pipeline's data quality metrics and drop nothing. The same three conditions build
the added columns:

| Column | Derivation |
|---|---|
| `regras_violadas` | array with the name of each failed rule; empty when none failed |
| `fl_registro_invalido` | `size(regras_violadas) > 0`; never null |
| `origem` | `'API'` |
| `data_carga` | `current_timestamp()` when the row was validated |

The table is partitioned, not clustered, by the flag. Liquid clustering rejects
`BOOLEAN` columns (`DELTA_CLUSTERING_COLUMNS_DATATYPE_NOT_SUPPORTED`), and a true/false
column gives only two partitions. This is a recorded exception to the constitution's
"no `PARTITIONED BY`" rule (feature 004 plan, Complexity Tracking).

The table is private: it is not in the catalog, and its counts are read from the
pipeline event log.

**Consumer rule**: a conformed silver table built from API events reads
`STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE NOT fl_registro_invalido`,
and does not restate the rules. Flagged rows go to `tb_quarentena`.

### tb_quarentena

[03_tb_quarentena.sql](../src/pipeline/02_silver/03_tb_quarentena.sql) — streaming
table `workspace.silver.tb_quarentena`. As built.

Every row of the validation table where `fl_registro_invalido` is true, with every
column of that table and nothing excluded, so that all the evidence of a data issue is in
one row:
- the event as delivered by `vw_bronze_dados_api`, unchanged;
- `regras_violadas`, `fl_registro_invalido` and `origem = 'API'`;
- `data_carga`, the time of validation;
- `data_carga_quarentena`, the time the row entered quarantine. The warn expectation
`regra_violada_registrada` (`size(regras_violadas) > 0`) checks that every row names at
least one rule. There is no hash key, because quarantine is not a conformed table.

**Reconciliation**: rows in `bronze.dados_api` = valid rows of the validation table +
rows in `tb_quarentena`. No exclusion is documented.

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
