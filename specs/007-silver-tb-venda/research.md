# Research: Silver Sales Table from API Events and Partner Files

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

Sources consulted: constitution v1.10.0; the `databricks-pipelines` skill
(`references/streaming-table-sql.md`, `expectations-sql.md`); features 004–006 (code,
contracts, data models and the counts of 2026-10-18); the generator in
`explorations/functions.py`; `doc/pipeline-reference.md` and `doc/known-issues.md`.

**The workspace could not be queried.** On 2026-10-28 the `databricks-free` login had
expired (`refresh token is invalid`). The facts below come from the code and from the
measurements of 2026-10-18. The three that need the data are measured in quickstart step
1 before the update, and each has a fallback.

## Facts established

| Fact | API (valid events with a payment) | Files (`workspace.bronze.dados_files`) |
|---|---|---|
| Rows on 2026-10-18 | not measured; a fraction of the 756,249 valid events with a user (`info_produto` is generated for about 30% of them, and a payment exists exactly when a product does) | 200,000 |
| Date of sale | `access_date`, a string; `try_to_timestamp` as in `tb_acesso` | `data_venda`, inferred as `DATE` |
| List price | `payload.info_produto.valor`, text `R$ 247,00` | `valor`, text `R$ 247,00` |
| Discount | `payload.info_pagamento.disconto`, a JSON number (`0.05`, `0.10`, `0.15`), null for about 70% | `disconto`, text `5%`, `10%` or `15%` by company; never null |
| Payment method | `credito`, `boleto`, `pix` (`-----` is in quarantine) | none; the request fixes `pix` |
| Installments | `payload.info_pagamento.quantidade_parcelas`, a JSON integer; `1` for boleto and pix, `1`, `2`, `3`, `10` or `12` for credit | none; the request fixes `1` |
| Installment value | `payload.info_pagamento.valor_parcelas`, a JSON number, rounded to cents by the generator | none |
| Paid amount | `payload.info_pagamento.valor` = list price − discount, exact to the cent | none |
| User key | as in `tb_acesso` and `tb_usuario` | as in `tb_usuario`; 200,000 keys for 200,000 rows |

Exact discount amounts, list price × discount, rounded to cents:

| Course | 5% | 10% | 15% |
|---|---|---|---|
| R$ 247,00 | 12.35 | 24.70 | 37.05 |
| R$ 997,00 | 49.85 | 99.70 | 149.55 |
| R$ 2497,00 | 124.85 | 249.70 | 374.55 |

All nine are exact in two decimal places, so decimal arithmetic reproduces them with no
rounding.

## Decision 1: Three files, as the diagram draws them

- **Decision**: `09_vw_silver_tb_venda_api.sql`, `10_vw_silver_tb_venda_files.sql`,
  `11_tb_venda.sql`. The target is an empty streaming table with five expectations; two
  flows, `silver_tb_venda_api_flow` and `silver_tb_venda_files_flow`, each
  `INSERT INTO workspace.silver.tb_venda BY NAME SELECT * FROM STREAM(<flow view>)`.
- **Rationale**: the diagram shows `T1 → V3 → S4` and `V2 → V4 → S4`. Principle V
  requires one append flow per source, each reading a flow view named
  `vw_<zone>_<target>_<source>` and numbered just before the target. The skill's
  `streaming-table-sql.md` gives the empty-target-plus-flows form, and forbids `AS SELECT`
  together with flows.
- **Alternatives considered**: a single `AS SELECT` with `UNION ALL` (forbidden by
  Principle V, and the earlier pipeline's form).

## Decision 2: Which API events are sales

- **Decision**: rows of `STREAM(workspace.silver.temp_tb_validacao_api)` with
  `NOT fl_registro_invalido AND payload.info_pagamento IS NOT NULL`.
- **Rationale**: feature 004's consumer rule requires conformed API tables to read the
  valid side of the validation table. A sale is an event with a payment (spec FR-003).
  In the generator a payment exists exactly when a product exists, so filtering on the
  payment alone is enough.
- **Alternatives considered**: filtering on the product (equivalent today, but it would
  admit a product without a payment as a sale with empty amounts).

## Decision 3: Reused keys, written character for character

- **Decision**:
  - The API view has an inner query that defines `timestamp_acesso`,
    `endereco_ip_acesso` and `local_acesso` with `05_tb_acesso.sql`'s expressions, then
    `acesso_uuid`, `usuario_uuid` and `curso_uuid` with the same text as that file. The
    outer query selects the 13 columns. `data_venda` is `timestamp_acesso`.
  - The files view copies `usuario_uuid` from `07_vw_silver_tb_usuario_files.sql`, and
    computes `curso_uuid` as `md5(curso)`.
- **Rationale**: Principle VI requires every dataset that computes a key to use the same
  expression, written identically. `tb_acesso` writes `acesso_uuid` over its own column
  aliases, so the view needs the same aliases to repeat it exactly. With the request's
  wording (`Computador` for every non-mobile point) the 5% of `unknown` access points
  would get a different key, the defect in `doc/known-issues.md`. `md5(curso)` equals the
  catalog's `md5(nome_curso)` (generator, `generate_database_data`).
- **Alternatives considered**: expanding the aliases inline (the same value, but not the
  same text, so a reviewer cannot compare the two files line by line); a shared key view
  (removed from the project under constitution v1.8.0).

## Decision 4: `venda_uuid` business columns

- **Decision**:
  - API: `md5(concat_ws('||', coalesce(cast(timestamp_acesso AS STRING), ''),
    coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, ''),
    coalesce(payload.info_produto.product_name, '')))`.
  - Files: `md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario,
    ''), coalesce(cast(data_venda AS STRING), ''), coalesce(curso, '')))`.
- **Rationale**: a site sale is one access event with one product; a corporate sale is
  one employee buying one course on one date. The record source is not a component:
  the two sources build the key from different kinds of columns, so they cannot issue the
  same identifier for different sales (Principle VI). The files key is unique because
  each employee occurs once (feature 006: 200,000 keys for 200,000 rows).
- **Risk and fallback**: the API key is expected to be unique, as `acesso_uuid` is in
  `tb_acesso` (0 repeated keys on 2026-10-18), but `tb_acesso` does not hold the events
  with the address `999.999.999.999`, and `tb_venda` does. Two such events in the same
  second, from the same kind of device, buying the same course would collide. Quickstart
  step 1 counts repeated keys before the update. If any exist, add
  `payload.info_usuario.nome` as a fifth component and record it here.
- **Applied 2026-10-28**: measured before the update, the four-component API key repeated
  1,311 times, in 624 groups, all from events with the address `999.999.999.999`. With
  `payload.info_usuario.nome` as a fifth component, 0 repeats. The API key is therefore
  `md5(concat_ws('||', coalesce(cast(timestamp_acesso AS STRING), ''),
  coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, ''),
  coalesce(payload.info_produto.product_name, ''), coalesce(payload.info_usuario.nome,
  '')))`.
- **Alternatives considered**: reusing `acesso_uuid` as the sale key (it is empty for
  corporate sales, and it names the access, not the sale).

## Decision 5: Decimal arithmetic for amounts and discounts

- **Decision**:
  - discount fraction: API `CAST(coalesce(payload.info_pagamento.disconto, 0) AS
    DECIMAL(5,2))`; files `CAST(replace(coalesce(disconto, '0%'), '%', '') AS
    DECIMAL(5,2)) / 100`, cast to `DECIMAL(5,2)`;
  - list price: `try_cast(replace(regexp_replace(<valor>, '[^0-9,]', ''), ',', '.') AS
    DECIMAL(9,2))`, which turns `R$ 2497,00` into `2497.00`;
  - `percentual_desconto`: API `concat(CAST(<fraction> * 100 AS INT), '%')`, so `0.15`
    gives `15%` and no discount gives `0%`; files `coalesce(disconto, '0%')`, the text
    as received, already in that form;
  - `valor_desconto`: `CAST(<list price> * <fraction> AS DECIMAL(9,2))`;
  - `valor_parcelas`: API `CAST(payload.info_pagamento.valor_parcelas AS DECIMAL(9,2))`;
    files `<list price> − valor_desconto`;
  - `valor_pago`: `CAST(quantidade_parcelas * valor_parcelas AS DECIMAL(9,2))`.
- **Rationale**: the bronze JSON numbers are inferred as `DOUBLE`. Turned into text, a
  double gives `5.0`, not `5`. Multiplied as doubles, the amounts can carry binary
  fractions. As decimals, every discount amount in the table above is exact. The
  `regexp_replace` keeps only digits and the decimal comma, so it does not depend on the
  `R$ ` prefix's spacing; the earlier pipeline's `replace(..., ',', '')` turned
  `R$ 247,00` into `24700` (`doc/known-issues.md`).
- **Alternatives considered**: `substr(valor, 4)` (depends on the prefix length);
  `format_number` (adds thousands separators).

## Decision 6: The installment field name

- **Decision**: read `payload.info_pagamento.valor_parcelas`.
- **Rationale**: the generator builds the struct with the key `valor_parcela`, but the
  column is declared with the type `StructType(... 'valor_parcelas' ...)`, and the struct
  is cast to the declared type before it is written, which renames fields by position.
  The JSON should therefore hold `valor_parcelas`, as the request expects.
- **Risk and fallback**: quickstart step 1 reads the payload's type from
  `information_schema`. If it shows `valor_parcela`, the API view reads that name
  instead, and the difference is recorded here and in `doc/pipeline-reference.md`. The
  dry run would fail on a missing field in any case.
- **Confirmed 2026-10-28**: the bronze payload holds `valor_parcelas` (`double`). No
  fallback.

## Decision 7: Installment rounding follows the request

- **Decision**: `valor_pago` = installments × installment value, as requested, even when
  it differs by cents from `payload.info_pagamento.valor`.
- **Rationale**: the generator rounds the installment value to cents, so for 3, 10 or 12
  installments the product can be a cent or two off (`2372.15 / 12 = 197.68`, × 12 =
  `2372.16`). The request defines the paid amount by this formula. Quickstart step 1
  counts the rows that differ and their total difference, so the owner sees the size of
  it.
- **Measured 2026-10-28**: 78,578 of 220,472 API sales differ, net −535.23 in total.
- **Alternatives considered**: taking `payload.info_pagamento.valor` as the paid amount
  (exact, but not what the request asks for). It remains available as a later change.

## Decision 8: Flow names

- **Decision**: unqualified `silver_tb_venda_api_flow` and `silver_tb_venda_files_flow`,
  the same form as `tb_usuario`'s flows.
- **Rationale**: feature 006 left open the finding that unqualified flow names appear
  under the pipeline's default schema, `workspace.bronze`, in the event log. The data is
  correct. Renaming a flow later restarts it and duplicates its rows, so the owner's
  decision on that finding should cover all flows at once. Until then, the new flows
  follow the existing form.
- **Alternatives considered**: qualified flow names for the new flows only (two
  conventions in one pipeline, before the owner has decided).

## Decision 9: Expectations

- **Decision**: five warn expectations on `tb_venda`, with explicit null handling:
  `check_venda_uuid` (`venda_uuid IS NOT NULL`), `check_usuario_uuid`,
  `check_curso_uuid`, `check_data_venda` (each `IS NOT NULL`), and `check_valor_pago`
  (`valor_pago IS NOT NULL AND valor_pago > 0`).
- **Rationale**: the request names no rule. Principle III requires at least one, and
  Principle VI requires the not-null rule on the hash key. Counting only keeps every row,
  so both sources reconcile with no exclusion (Principle IV).
- **Expected failures**: 0 for every rule. `check_valor_pago` would catch a price that
  cannot be read or a zero amount; the quarantine already removes the API's `0.00`
  payments.

## Expected counts

Measured in quickstart step 1, after the login is renewed:

```text
API sales   = valid events with a payment                      (step 1)
Files sales = rows of workspace.bronze.dados_files              (200,000 on 2026-10-18)
tb_venda    = API sales + files sales
Every expectation: 0 failed
```
