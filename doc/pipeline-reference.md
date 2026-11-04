# Pipeline reference

Every dataset of the pipeline, in dependency order. Tables carry a `quality`
table property (`bronze`, `silver` or `gold`).

The Bronze section, and in Silver the views `vw_bronze_dados_api` and
`vw_bronze_dados_files`, the course feed view `vw_bronze_tb_curso`, the flow views
`vw_silver_tb_usuario_api`, `vw_silver_tb_usuario_files`, `vw_silver_tb_venda_api` and
`vw_silver_tb_venda_files`, and the sections `temp_tb_validacao_api`, `tb_quarentena`,
`tb_acesso`, `tb_usuario`, `tb_venda` and `tb_curso`, and in Gold the section
`dim_usuario` with its flow view, describe the pipeline as it is built today, under [src/pipeline/](../src/pipeline/). The other Silver datasets and the Gold
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
| `vw_bronze_dados_files` | [02](../src/pipeline/02_silver/02_vw_bronze_dados_files.sql) | `STREAM(bronze.dados_files)` minus `source_file_name`, `_rescued_data`; the bronze-to-silver boundary of the files source. As built |
| `vw_silver_tb_usuario_api` | [06](../src/pipeline/02_silver/06_vw_silver_tb_usuario_api.sql) | flow view: valid API events with a user, in `tb_usuario`'s 10 columns, `usuario_uuid` included. As built |
| `vw_silver_tb_usuario_files` | [07](../src/pipeline/02_silver/07_vw_silver_tb_usuario_files.sql) | flow view: `vw_bronze_dados_files` in `tb_usuario`'s 10 columns, `usuario_uuid` included. As built |
| `vw_silver_tb_venda_api` | [09](../src/pipeline/02_silver/09_vw_silver_tb_venda_api.sql) | flow view: valid API events with a payment, in `tb_venda`'s 13 columns, with the access, user and course keys written as in `tb_acesso`. As built |
| `vw_silver_tb_venda_files` | [10](../src/pipeline/02_silver/10_vw_silver_tb_venda_files.sql) | flow view: `vw_bronze_dados_files` in `tb_venda`'s 13 columns, user key as in `tb_usuario`. As built |
| `vw_bronze_tb_curso` | [12](../src/pipeline/02_silver/12_vw_bronze_tb_curso.sql) | the course feed's boundary view (constitution v1.11.0, Principle I): `STREAM(bronze.dados_database)` minus `source_file_name`, `_rescued_data`, with `valor_curso` as `DECIMAL(9,2)` and `origem = 'DATABASE'`, `data_carga` added; no filter. Read by `tb_curso` and, later, `dim_curso`. As built |

### temp_tb_validacao_api

[03_temp_tb_validacao_api.sql](../src/pipeline/02_silver/03_temp_tb_validacao_api.sql)
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

[04_tb_quarentena.sql](../src/pipeline/02_silver/04_tb_quarentena.sql) — streaming
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
rows in `tb_quarentena`. Downstream of validation, one exclusion is declared: rows that
`tb_acesso` drops through `check_endereco_ip_acesso`. They are not quarantined
(constitution v1.7.0, Principle IV), and the rule's failed count records them.

### tb_acesso

[05_tb_acesso.sql](../src/pipeline/02_silver/05_tb_acesso.sql) — streaming table
`workspace.silver.tb_acesso`. As built. One row per valid API access whose address is not
`999.999.999.999`. It reads `STREAM(workspace.silver.temp_tb_validacao_api)` with
`WHERE NOT fl_registro_invalido`, and computes its three keys inline.

| Column | Derivation |
|---|---|
| `timestamp_acesso` | `try_to_timestamp(access_date)` |
| `endereco_ip_acesso` | `ip_address` |
| `local_acesso` | `Mobile` for `iphone`/`android`, `Computador` for `chrome`/`safari`/`firefox`, otherwise `unknown` (case-insensitive) |
| `acesso_uuid` | `md5(concat_ws('\|\|', timestamp_acesso, endereco_ip_acesso, local_acesso))`, each component cast to string and `coalesce`d to `''` |
| `usuario_uuid` | `md5(concat_ws('\|\|', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome))`; null when the event has no user |
| `curso_uuid` | `md5(payload.info_produto.product_name)`; null when the event has no product |
| `origem` | `'API'` |
| `data_carga` | `current_timestamp()` |

Business key columns of the hash keys:

| Key | Business key columns | Defined in |
|---|---|---|
| `acesso_uuid` | `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso` | `05_tb_acesso.sql` |
| `usuario_uuid` | `access_date` (as timestamp), `payload.info_usuario.nome` | `05_tb_acesso.sql` and `06_vw_silver_tb_usuario_api.sql`, same expression |
| `curso_uuid` | `payload.info_produto.product_name`; equals the catalog's `curso_uuid` (`md5(nome_curso)`) | `05_tb_acesso.sql` |

The table shows the three expectation actions:

| Expectation | Rule | On violation |
|---|---|---|
| `check_endereco_ip_acesso` | `endereco_ip_acesso` is null or not `'999.999.999.999'` | drop row; a declared exclusion, not quarantined (constitution v1.7.0, Principle IV) |
| `check_local_acesso` | `local_acesso != 'unknown'` | record only; the `FAIL UPDATE` variant is on the next line, commented out |
| `check_timestamp_acesso` | `timestamp_acesso IS NOT NULL` | record only |
| `check_acesso_uuid` | `acesso_uuid IS NOT NULL` | record only; `acesso_uuid` is also unique in the table |

Expectation metrics count every row of the query, including rows that another rule
drops. `check_local_acesso` reported 118,305 failures on 2026-10-18, while the table keeps
117,131 `unknown` rows. The other 1,174 also had the impossible address and were dropped.

**Reconciliation**: valid API events = rows in `tb_acesso` + rows dropped by
`check_endereco_ip_acesso`. On 2026-10-18 that was 2,541,715 = 2,516,192 + 25,523.

### tb_usuario

[08_tb_usuario.sql](../src/pipeline/02_silver/08_tb_usuario.sql) — streaming table
`workspace.silver.tb_usuario`. As built. Fed by two append flows, one per source. Each
flow is only `INSERT INTO ... BY NAME SELECT * FROM STREAM(<view>)`; its logic lives in
its flow view (constitution v1.9.0, Principle V):
- `silver_tb_usuario_api_flow` from `vw_silver_tb_usuario_api` (valid events of
  `temp_tb_validacao_api` with a user);
- `silver_tb_usuario_files_flow` from `vw_silver_tb_usuario_files` (`vw_bronze_dados_files`).

`usuario_uuid` is unique because each key occurs once in both sources. The table appends
and does not merge, so uniqueness is verified after each load. A re-delivered employee
would show up as a repeated key.

| Column | From API | From files |
|---|---|---|
| `usuario_uuid` | `md5(concat_ws('\|\|', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome))` (same expression as `tb_acesso`) | `md5(concat_ws('\|\|', coalesce(nome_empresa, ''), coalesce(nome_funcionario, '')))` |
| `nome_usuario` | `payload.info_usuario.nome` | `nome_funcionario` |
| `email_usuario` | `payload.info_usuario.email` | `email_funcionario` |
| `idade_usuario` | `try_cast(payload.info_usuario.idade AS INT)` | `try_cast(idade AS INT)` |
| `sexo_usuario` | `payload.info_usuario.sexo` | `sexo` |
| `estado_usuario` | `payload.info_usuario.estado` | `estado` |
| `profissao_usuario` | `payload.info_usuario.profissao` | `profissao` |
| `empresa_usuario` | null | `nome_empresa` |
| `origem` | `'API'` | `'ARQUIVO'` |
| `data_carga` | load timestamp | load timestamp |

API rows come only from valid events that carry a user. Business key columns:

| Key | Business key columns | Defined in |
|---|---|---|
| `usuario_uuid` (API) | `access_date` (as timestamp), `payload.info_usuario.nome` | `05_tb_acesso.sql` and `06_vw_silver_tb_usuario_api.sql`, same expression |
| `usuario_uuid` (ARQUIVO) | `nome_empresa`, `nome_funcionario` | `07_vw_silver_tb_usuario_files.sql` |

| Expectation | Rule | On violation |
|---|---|---|
| `check_sexo_usuario` | `sexo_usuario` is `M` or `F` (null fails) | drop row; a declared exclusion, not quarantined (constitution v1.7.0, Principle IV) |
| `check_email_usuario` | `email_usuario` contains `@` (null fails) | record only |
| `check_usuario_uuid` | `usuario_uuid IS NOT NULL` | record only |

**Reconciliation**: candidate users of both sources = rows in `tb_usuario` + rows
dropped by `check_sexo_usuario`.

### tb_venda

[11_tb_venda.sql](../src/pipeline/02_silver/11_tb_venda.sql) — streaming table
`workspace.silver.tb_venda`. As built. One row per sale. Fed by two append flows, each
`INSERT INTO ... BY NAME SELECT * FROM STREAM(<view>)`; its logic lives in its flow view
(constitution v1.9.0):
- `silver_tb_venda_api_flow` from `vw_silver_tb_venda_api` (valid events of
  `temp_tb_validacao_api` that carry `payload.info_pagamento`);
- `silver_tb_venda_files_flow` from `vw_silver_tb_venda_files` (`vw_bronze_dados_files`).

`<preco>` is the list price, parsed from text such as `R$ 2497,00` with
`try_cast(replace(regexp_replace(<valor>, '[^0-9,]', ''), ',', '.') AS DECIMAL(9,2))`.
`<fracao>` is the discount fraction as `DECIMAL(5,2)`: `payload.info_pagamento.disconto`
(a `double`, `0` when null) for the API, `disconto` (`5%`) divided by 100 for the files.
All amounts are computed as decimals.

| Column | From API | From files |
|---|---|---|
| `venda_uuid` | `md5(concat_ws('\|\|', timestamp_acesso, endereco_ip_acesso, local_acesso, product_name, nome))`, each component cast to string and `coalesce`d to `''` | `md5(concat_ws('\|\|', nome_empresa, nome_funcionario, data_venda, curso))`, same rule |
| `data_venda` | `try_to_timestamp(access_date)` | `CAST(data_venda AS TIMESTAMP)` (midnight) |
| `acesso_uuid` | same expression as `tb_acesso` | null |
| `usuario_uuid` | same expression as `tb_acesso` and `tb_usuario` | same expression as `tb_usuario`'s files rows |
| `curso_uuid` | `md5(payload.info_produto.product_name)` | `md5(curso)` |
| `forma_pagamento` | `payload.info_pagamento.forma_pagamento` | `'pix'` |
| `quantidade_parcelas` (INT) | `try_cast(payload.info_pagamento.quantidade_parcelas AS INT)` | `1` |
| `valor_parcelas` (DECIMAL(9,2)) | `payload.info_pagamento.valor_parcelas` | `<preco>` − `valor_desconto` |
| `valor_pago` (DECIMAL(9,2)) | `quantidade_parcelas` × `valor_parcelas` | same |
| `percentual_desconto` | `<fracao>` × 100 as a whole number, then `%`; `0%` when none | `disconto` as received; `0%` when empty |
| `valor_desconto` (DECIMAL(9,2)) | `<preco>` × `<fracao>` | same |
| `origem` | `'API'` | `'ARQUIVO'` |
| `data_carga` | load timestamp | load timestamp |

Business key columns:

| Key | Business key columns | Defined in |
|---|---|---|
| `venda_uuid` (API) | `access_date` (as timestamp), `ip_address`, the access location, `payload.info_produto.product_name`, `payload.info_usuario.nome` | `09_vw_silver_tb_venda_api.sql` |
| `venda_uuid` (ARQUIVO) | `nome_empresa`, `nome_funcionario`, `data_venda`, `curso` | `10_vw_silver_tb_venda_files.sql` |

The user name is part of the API sale key because, without it, 1,311 API sales repeated
the key: all from events with the address `999.999.999.999`, which `tb_acesso` drops. The
same events share `acesso_uuid` values among themselves; none of them joins `tb_acesso`.

| Expectation | Rule | On violation |
|---|---|---|
| `check_venda_uuid` | `venda_uuid IS NOT NULL` | record only; `venda_uuid` is also unique in the table |
| `check_usuario_uuid` | `usuario_uuid IS NOT NULL` | record only |
| `check_curso_uuid` | `curso_uuid IS NOT NULL` | record only |
| `check_data_venda` | `data_venda IS NOT NULL` | record only |
| `check_valor_pago` | `valor_pago IS NOT NULL AND valor_pago > 0` | record only |

No rule drops a row. On 2026-10-28 every rule passed all 420,472 rows.

**Reconciliation**: API sales = valid API events with a payment (220,472 on 2026-10-28);
files sales = rows in `bronze.dados_files` (200,000). No exclusion.

**Keys that do not join**, by design, counted on 2026-10-28:
- 2,174 API sales have an `acesso_uuid` with no row in `tb_acesso`: their event had the
  address `999.999.999.999`;
- 4,362 sales have a `usuario_uuid` with no row in `tb_usuario`: their user's sex is not
  `M` or `F`.

Gold resolves them to an "unknown" member.

**Installments**: the payload rounds the installment value to cents, so `valor_pago`
differs by a cent or two from `payload.info_pagamento.valor` in 78,578 API sales, net
−535.23 in total. `valor_pago` follows the requested formula.

### tb_curso

[13_tb_curso.sql](../src/pipeline/02_silver/13_tb_curso.sql) — streaming table
`workspace.silver.tb_curso`, target of the `AUTO CDC` flow `silver_tb_curso_flow`, stored
as **SCD type 1**. As built. One row per course: the values of its latest change; a
deleted course has no row.

| Setting | Value |
|---|---|
| Source | `STREAM(vw_bronze_tb_curso)` |
| Key | `curso_uuid`, the identifier delivered by the source (no hash key: Principle VI exception) |
| Sequence | `timestamp_change` |
| Delete condition | `change_type = 'delete'`, placed before `SEQUENCE BY` |
| Columns excluded | `COLUMNS * EXCEPT (change_type, timestamp_change, processing_time)`; the view already excludes `source_file_name` and `_rescued_data` |

| Column | Type | From |
|---|---|---|
| `curso_uuid` | STRING | as delivered; equals `md5(nome_curso)`, the value sales and accesses carry |
| `nome_curso` | STRING | as delivered |
| `nivel_curso` | STRING | as delivered |
| `valor_curso` | DECIMAL(9,2) | `CAST(valor_curso AS DECIMAL(9,2))` in the view |
| `origem` | STRING | `'DATABASE'` |
| `data_carga` | TIMESTAMP | load time of the change that last set the row |

| Expectation | Rule | On violation |
|---|---|---|
| `check_curso_uuid` | `curso_uuid IS NOT NULL` | record only |
| `check_nome_curso` | `nome_curso IS NOT NULL` | record only |
| `check_valor_curso` | `valor_curso IS NOT NULL AND valor_curso > 0` | record only |

On 2026-10-28 the feed held the three inserts, and the table holds three rows:
`beginner` 247.00, `intermediate` 997.00, `advanced` 2497.00. Every rule passed 3, failed
0. Every `curso_uuid` in `tb_venda` and `tb_acesso` has a row.

**Reconciliation**: rows = distinct courses whose latest change is not a deletion.

**Updates and deletions** are shown at the talk, not run during implementation: the
generator's `update row` sets the beginner course to 147.00 (still 3 rows), and
`delete row` removes it (2 rows). After the deletion, that course's sales and accesses no
longer join `tb_curso`; `dim_curso` keeps its history.

A consumer that reads `tb_curso` as a stream needs `WITH (SKIPCHANGECOMMITS)`, because
the table is updated and deleted in place.

## Gold

### dim_tempo (outside the pipeline)

Calendar dimension created by the last cell of
[functions.py](../explorations/functions.py), one row per day from 2024-06-01 to
2026-12-31. Columns: `sk_tempo`, `data`, `ano`, `mes` (Portuguese month name),
`mes_ano` (month number), `dia_semana_int`, `dia_semana` (Portuguese day name),
`fl_dia_semana` (true Monday–Friday), `dia_mes`, `fl_ultimo_dia_mes`, `dia_ano`,
`semana_ano`, `bimestre`, `trimestre`, `semestre`, `data_carga`.

### dim_usuario

[02_dim_usuario.sql](../src/pipeline/03_gold/02_dim_usuario.sql) — streaming table
`workspace.gold.dim_usuario`, target of the `AUTO CDC` flow
`gold_dim_usuario_tb_usuario_flow`. As built. Grain: one user. **SCD type 1**: key
`usuario_uuid`, sequence silver's `data_carga`, no history. Silver delivers no delete event,
so the flow has no delete condition, and a user removed from silver keeps its row.

It reads [vw_gold_dim_usuario_tb_usuario](../src/pipeline/03_gold/01_vw_gold_dim_usuario_tb_usuario.sql),
a temporary view over `STREAM(silver.tb_usuario)` that computes the key and `data_carga`.

| Column | Type | From |
|---|---|---|
| `sk_usuario` | BIGINT | `xxhash64(usuario_uuid) & 9223372036854775807`; `-1` and `-2` for the members |
| `usuario_uuid` | STRING | business key, the silver hash key; `'-1'` and `'-2'` for the members |
| `nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`, `profissao_usuario`, `empresa_usuario`, `origem` | STRING | silver, unchanged; the member's label for the members |
| `idade_usuario` | INT | silver, unchanged; null for the members |
| `data_carga` | TIMESTAMP | `current_timestamp()`: the time gold last wrote the row, not silver's load time. It does not move on an update with no new data |

**Surrogate key.** `sk_usuario` is a deterministic function of the business key, so it does
not depend on any stored state. Identity columns are not supported on `AUTO CDC` targets. The
mask clears the sign bit, so **only the members have a negative key**, and `sk_usuario < 0`
selects them.

**Default members**: `-1` / `'-1'` "Desconhecido" (unknown) and `-2` / `'-2'` "Não se aplica"
(not applicable). Spark rejects a `UNION` of a stream and literal rows, so each silver row
emits three rows, the user and the two members, and the flow keeps one row per key: about 2.8
million rows emitted on the first load for 941,236 kept. The members appear with the first
silver row that reaches gold. Facts resolve `sk_usuario` by joining on `usuario_uuid`; they
use `-1` when there is no match (4,362 sales users on 2026-11-04, whose sex failed silver's
rule) and `-2` when the fact has no user by nature.

**Expectations**: none, because the feature's spec requests none (constitution v2.0.0,
Principle III). A null key does not stop an update, so keys are verified by query.

On 2026-11-04: 941,236 rows (`API` 741,234, `ARQUIVO` 200,000, 2 members), every key unique
and present, and every attribute equal to silver's. A second update with no new data left
every key and `data_carga` unchanged.

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
