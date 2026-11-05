# Data generation

All demo data is synthetic. It is produced by
[explorations/functions.py](../explorations/functions.py), a Databricks notebook
that other notebooks load with `%run "./functions"`. It uses
[dbldatagen](https://github.com/databrickslabs/dbldatagen), installed by the
first cell.

Running the notebook has two effects: it installs `dbldatagen` and defines the
three generator functions below.

## generate_api_data(number_rows, run_as_batch=False)

Simulates the site API. Starts a structured streaming query named
`generate_api_stream_data` that writes JSON to
`/Volumes/workspace/bronze/landing/stream`, with its checkpoint in
`/Volumes/workspace/bronze/landing/_checkpoint_stream`. Returns the query handle.

| Parameter | Effect |
|---|---|
| `number_rows` | Passed to the generator as `rowsPerSecond` |
| `run_as_batch` | `True` adds `trigger(availableNow=True)`, required on Databricks Free Edition, which cannot run a continuous stream. `False` runs continuously until stopped. |

Each event has `access_date` (2024-06-01 to 2025-12-31), `ip_address`,
`access_point` and a nested `payload`:

```
payload
├── info_usuario    nome, idade, sexo, email, profissao, estado
├── info_produto    product_name, valor            ("R$ 247,00")
└── info_pagamento  disconto, valor, forma_pagamento, quantidade_parcelas, valor_parcelas
```

The payload models a funnel: about 70% of events have no `info_usuario` (an
anonymous visit); `info_produto` exists only when there is a user, and
`info_pagamento` only when there is a product.

### Bad records injected on purpose

These exist so the pipeline's expectations and quarantine have something to catch.

| Field | Bad value | Share | Handled by |
|---|---|---|---|
| `product_name` | `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` | 4% | quarantine |
| `info_pagamento.valor` | `0.00` (price of the placeholder course) | 4% | quarantine |
| `forma_pagamento` | `-----` | 3% | quarantine |
| `ip_address` | `999.999.999.999` | ~1% | dropped from `tb_acesso` |
| `access_point` | `unknown` | 5% | recorded on `tb_acesso` |
| `sexo` | `X` | 2% | dropped from `tb_usuario` |
| `email` | `#yahoo.com` / `#google.com` (no `@`) | 4% | recorded on `tb_usuario` |

### Value distributions

| Field | Values (weight) |
|---|---|
| Course | Construindo um Data Lakehouse com SQL e DLT — R$ 247 (30), Mastering SQL no Databricks — R$ 997 (21), Programa Data Heroes — R$ 2497 (45) |
| Access point | iphone (30), android (20), chrome (20), firefox (15), safari (10) |
| Payment method | credito (69), boleto (24), pix (4) |
| Discount | none (70%), otherwise 5% (50), 10% (35), 15% (15) |
| Installments | 1 for boleto and pix; for credit 1, 2, 3, 10 or 12 |

## generate_files_data(number_rows)

Simulates a partner company sending a batch of corporate sales. Appends one CSV
file with `number_rows` rows to `/Volumes/workspace/bronze/landing/files`, then
removes Spark's `_committed`, `_started` and `_SUCCESS` marker files so Auto
Loader sees only data.

Columns: `data_venda`, `nome_empresa`, `sexo`, `nome_funcionario`,
`email_funcionario`, `profissao`, `idade`, `estado`, `curso`, `valor`, `disconto`.

There are 13 companies (`Empresa A` … `Empresa N`). The discount depends on the
company: 5% for A, G and H; 10% for D, E and F; 15% for the rest. This source
contains no bad records.

## generate_database_data(type_of_data='initial setup')

Simulates a CDC feed from the course catalog database. Writes a CSV file to
`/Volumes/workspace/bronze/landing/database` with columns `curso_uuid`,
`nome_curso`, `nivel_curso`, `valor_curso`, `change_type`, `timestamp_change`.

| `type_of_data` | Writes | Mode |
|---|---|---|
| `'initial setup'` | Three `insert` rows, one per course (beginner 247, intermediate 997, advanced 2497) | overwrite |
| `'update row'` | An `update` changing *Construindo um Data Lakehouse com SQL e DLT* to 147.00 | append |
| `'delete row'` | A `delete` for the same course | append |

`curso_uuid` is `md5(nome_curso)`, the same expression the silver layer uses to
derive course keys from sales, which is what lets sales join to courses.

## dim_tempo

The calendar is not generated here. It is created by the setup script
[04_dim_tempo.sql](../explorations/setup/04_dim_tempo.sql); see
[getting-started.md](getting-started.md#create-the-calendar-dimension).
