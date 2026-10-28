# Feature Specification: Silver Sales Table from API Events and Partner Files

**Feature Branch**: `007-silver-tb-venda`

**Created**: 2026-10-28

**Status**: Draft

**Input**: User description: "generate the tb_venda table load. the tb_venda will have 2 sources - bronze_api and bronze_files. from bronze_api the table must have the follow fields: 1. data_venda as timestamp, 2. acesso_uuid where will be a uuid field thar will concatenate the follow fields: timestamp_acesso AS timestamp, ip_address, an field that will be based on the follow: if access_point is iphone or android, Mobile, else Computador 3. usuario_uuid where will be a uuid field thar will concatenate the follow fields: access_date as timestamp and info_usuario.name from the payload field. 4. curso_uuid where will be a uuid field for info_produto.product_name from payload. 5. forma_pagamento from info_pagamento within the payload. 6. quantidade_parcelas from info_pagamento within the payload quantidade_parcelas as int 7. valor_parcelas from info_pagamento within the payload valor_parcelas as decimal(9,2). 8. valor_pago where: quantidade_de_parcelas * valor_parcelas as decimal(9,2). 9. percentual_disconto where: disconto from payload.info_pagamento as needs mutiple per 100 and concatenate with % as string. 10. valor_desconto where will be got from by multiply the valor from payload.info_produto per the disconto info_pagamento payload field. 11. origem 12. data_carga. from bronze_files the table must have the follow fields: 1. data_venda as timestamp, 2. acesso_uuid as null and string datatype 3. usuario_uuid where will be a uuid field thar will concatenate the follow fields: nome_empresa and nome_funcionario. 4. curso_uuid where will be a uuid field based on curso field 5. forma_pagamento with the constant 'pix' as a returned value 6. quantidade_parcelas with the constant 1 as a returned value 7. valor_parcelas from info_pagamento within the payload valor_parcelas as decimal(9,2). 8. valor_pago where: quantidade_de_parcelas * valor_parcelas as decimal(9,2). 9. percentual_disconto from disconto field 10. valor_desconto based on the fields valor and disconto as decimal data type 11. origem 12. data_carga."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Site sales in one conformed table (Priority: P1)

As the project owner, I want every valid site event that carries a payment to become a
row of `workspace.silver.tb_venda`, with its date, payment method, installments, amounts
and discount, so that site revenue can be analysed.

**Why this priority**: the API is the source of most sales, and the keys a sale needs
(access, user, course) already exist for it (features 005 and 006).

**Independent Test**: after a run, every valid API event with a payment has exactly one
row in `tb_venda` with `origem = 'API'`, and its access and user keys equal those of the
same event in `tb_acesso` and `tb_usuario`.

**Acceptance Scenarios**:

1. **Given** a valid API event with a payment, **When** the run completes, **Then**
   `tb_venda` has one row with the event's time as `data_venda`, its payment method, its
   number of installments as a whole number, its installment value, the amount paid, the
   discount as a percentage text and as an amount, and `origem = 'API'`.
2. **Given** a valid API event without a payment (an anonymous visit, or a user who did
   not buy), **When** the run completes, **Then** it produces no row in `tb_venda`.
3. **Given** an API event in quarantine, **When** the run completes, **Then** it produces
   no row in `tb_venda`.
4. **Given** an API sale, **When** its `acesso_uuid`, `usuario_uuid` and `curso_uuid` are
   compared with `tb_acesso`, `tb_usuario` and the course catalog, **Then** each is the
   same value those tables hold for the same event, user and course.
5. **Given** an API sale whose access point is not recognized, **When** its `acesso_uuid`
   is compared with `tb_acesso`, **Then** it is equal, because both are built from the
   same access location value, `unknown` included.

---

### User Story 2 - Partner company sales in the same table (Priority: P1)

As the project owner, I want every corporate sale in the partner companies' files to
become a row of the same table, so that site and corporate revenue can be analysed
together.

**Why this priority**: the request puts both sources in one table. Without the files
source, corporate revenue would be missing from every later analysis.

**Independent Test**: after a run, every row of the sales files has exactly one row in
`tb_venda` with `origem = 'ARQUIVO'`, no access key, payment method `pix`, one
installment, and a user key equal to the employee's key in `tb_usuario`.

**Acceptance Scenarios**:

1. **Given** a sales file row, **When** the run completes, **Then** `tb_venda` has one row
   with the sale date as a timestamp, an empty `acesso_uuid`, a `usuario_uuid` derived
   from the company and the employee, a `curso_uuid` derived from the course, payment
   method `pix`, `1` installment, and `origem = 'ARQUIVO'`.
2. **Given** a sale of a course listed at `R$ 997,00` to a company with a `10%` discount,
   **When** the run completes, **Then** the discount is `10%` and `99.70`, and the
   installment value and the amount paid are both `897.30`.
3. **Given** a corporate sale, **When** its `usuario_uuid` is compared with
   `tb_usuario`, **Then** it is the same value as the employee's row there.

---

### User Story 3 - Amounts and discounts that compare across sources (Priority: P2)

As the project owner, I want amounts and discounts in the same form for both sources,
with no empty amounts, so that totals and discount analyses add up without special
cases.

**Why this priority**: the earlier pipeline computed corporate amounts wrongly and left
undiscounted sales without a discount value, which removed most sales from the gold fact
(`doc/known-issues.md`). This story keeps those defects out of the new table.

**Independent Test**: after a run, every discount text is one of `0%`, `5%`, `10%`,
`15%` in both sources, no amount is empty or negative, and the corporate discount
amounts equal list price times discount for every row.

**Acceptance Scenarios**:

1. **Given** an API sale with a discount of `0.15`, **When** the run completes, **Then**
   its discount text is `15%`, the same form the files source uses.
2. **Given** a sale without a discount, **When** the run completes, **Then** its
   discount text is `0%` and its discount amount is `0.00`.
3. **Given** an API sale of a course listed at `R$ 2497,00` with a `5%` discount,
   **When** the run completes, **Then** its discount amount is `124.85`.

---

### Edge Cases

- **Installment rounding.** The payload's installment value is rounded to cents, so
  installments × installment value can differ by a few cents from the paid amount in the
  payload (for example `2372.15` paid in 12 installments of `197.68` gives `2372.16`).
  The table follows the request: the amount paid is installments × installment value.
  Planning measures how many rows differ and by how much.
- **Sale whose access was dropped.** `tb_acesso` drops events with the address
  `999.999.999.999`. The sale itself is valid and stays in `tb_venda`; its `acesso_uuid`
  then has no row in `tb_acesso`. These sales are counted and explained.
- **Sale whose user was dropped.** `tb_usuario` drops users whose sex is not `M` or `F`.
  Their sales stay in `tb_venda`; their `usuario_uuid` has no row in `tb_usuario`. These
  sales are counted and explained.
- **Unrecognized access point.** The access location is `unknown`, as in `tb_acesso`, so
  the access key still matches.
- **A product without a payment.** The generator always gives a product a payment, so
  none is expected. Such an event would not be a sale and would produce no row.
- **List price that cannot be read.** All three courses have a readable list price
  (`R$ 247,00`, `R$ 997,00`, `R$ 2497,00`). A price that cannot be read leaves the
  discount amount empty; the row is kept and the not-empty rule on amounts counts it.
- **Payload field name.** The generator builds the installment value under the name
  `valor_parcela` but declares it as `valor_parcelas`. Planning confirms which name the
  bronze table holds.
- **The same employee buys twice.** Each sale is its own row with its own `venda_uuid`;
  both rows carry the same `usuario_uuid`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a conformed silver table
  `workspace.silver.tb_venda`, fed incrementally from two sources: the valid API events
  of feature 004, and the partner companies' sales files in
  `workspace.bronze.dados_files`.
- **FR-002**: The table MUST have these columns, filled per source as follows:

  | Column | Type | From API events | From sales files |
  |---|---|---|---|
  | `venda_uuid` | STRING | key of the sale (FR-006) | key of the sale (FR-006) |
  | `data_venda` | TIMESTAMP | `access_date`, as a timestamp | `data_venda`, as a timestamp |
  | `acesso_uuid` | STRING | the event's access key (FR-005) | empty |
  | `usuario_uuid` | STRING | the event's user key (FR-005) | key from `nome_empresa` and `nome_funcionario` (FR-005) |
  | `curso_uuid` | STRING | key from `payload.info_produto.product_name` | key from `curso` |
  | `forma_pagamento` | STRING | `payload.info_pagamento.forma_pagamento` | `pix` |
  | `quantidade_parcelas` | INT | `payload.info_pagamento.quantidade_parcelas`, as a whole number | `1` |
  | `valor_parcelas` | DECIMAL(9,2) | `payload.info_pagamento.valor_parcelas` | list price − discount amount |
  | `valor_pago` | DECIMAL(9,2) | `quantidade_parcelas` × `valor_parcelas` | `quantidade_parcelas` × `valor_parcelas` |
  | `percentual_desconto` | STRING | `payload.info_pagamento.disconto` × 100, as `5%` | `disconto`, as received |
  | `valor_desconto` | DECIMAL(9,2) | list price (`payload.info_produto.valor`) × `disconto` | list price (`valor`) × `disconto` |
  | `origem` | STRING | `API` | `ARQUIVO` |
  | `data_carga` | TIMESTAMP | load time | load time |

- **FR-003**: The API rows MUST come only from valid events that carry a payment, one row
  per event. Quarantined events and events without a payment MUST NOT produce a row.
- **FR-004**: The files rows MUST come from every row of `workspace.bronze.dados_files`,
  one row per sale, read through its existing boundary view.
- **FR-005**: `acesso_uuid`, `usuario_uuid` and `curso_uuid` MUST be the values already
  defined for each source, written with the same expression, so that sales join their
  access, user and course:
  - API `acesso_uuid`: the key of `tb_acesso` (feature 005), whose access location is
    `Mobile`, `Computador` or `unknown`;
  - API `usuario_uuid`: the key of `tb_acesso` and `tb_usuario` (features 005 and 006);
  - files `usuario_uuid`: the key of `tb_usuario`'s files rows (feature 006);
  - `curso_uuid`: equal to the course catalog's identifier, in both sources.
- **FR-006**: The table MUST carry `venda_uuid`, a deterministic hash key that identifies
  the sale, as the constitution requires of every conformed silver table. Its business
  key columns are:
  - API: the access time, the address, the access location, the course name and the
    user name (the user name was added on 2026-10-28, after 1,311 repeated keys were
    measured among events with the address `999.999.999.999`);
  - files: the company, the employee name, the sale date and the course.

  `venda_uuid` MUST be unique in the table and MUST be verified after every load.
- **FR-007**: `percentual_desconto` MUST be a whole-number percentage followed by `%`
  (`5%`, `10%`, `15%`), the same form in both sources. A sale without a discount MUST
  have `0%`.
- **FR-008**: `valor_desconto` MUST be the course's list price times the discount
  fraction. List prices arrive as text such as `R$ 247,00` and MUST be read as `247.00`.
  A sale without a discount MUST have `0.00`.
- **FR-009**: `valor_pago` MUST be `quantidade_parcelas` × `valor_parcelas`. For the files
  source, `valor_parcelas` MUST be the list price minus `valor_desconto`, since a
  corporate sale is a single `pix` payment.
- **FR-010**: Each source MUST feed the table through its own flow, whose whole query
  lives in its own view (constitution v1.9.0). Sources MUST NOT be combined into one
  query.
- **FR-011**: The table MUST declare these rules, each of which only counts failures and
  removes no row:
  - `check_venda_uuid`: `venda_uuid` is not empty;
  - `check_usuario_uuid`: `usuario_uuid` is not empty;
  - `check_curso_uuid`: `curso_uuid` is not empty;
  - `check_data_venda`: `data_venda` is not empty;
  - `check_valor_pago`: `valor_pago` is greater than zero (an empty amount fails).
- **FR-012**: The table MUST carry `quality` = `silver`.
- **FR-013**: Rows already loaded MUST NOT be loaded again by a later run.
- **FR-014**: The definitions MUST follow the constitution: SQL, current syntax, declared
  as streaming, numbered files in the silver folder, and no AI Functions in the pipeline
  (v1.10.0).
- **FR-015**: The table, its sources, keys and rules MUST be described in the project
  documentation, replacing the earlier pipeline's description of `tb_venda`. The business
  key columns of `venda_uuid` MUST be listed, and the known issues that concern the
  earlier `tb_venda` MUST be updated.

### Key Entities

- **Sale** (`tb_venda` row): one purchase of one course, either on the site (one valid
  API event with a payment) or by a partner company for an employee (one sales file row).
  Identified by `venda_uuid`.
- **Site sale**: taken from the payment part of a valid API event. Refers to its access
  (`tb_acesso`), its user (`tb_usuario`) and its course through their keys.
- **Corporate sale**: taken from a sales file row. Refers to its employee (`tb_usuario`)
  and its course through their keys. It has no access.
- **Sale rules**: the five counting rules of FR-011.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: API rows in `tb_venda` = valid API events with a payment, with a difference
  of 0.
- **SC-002**: Files rows in `tb_venda` = rows in `workspace.bronze.dados_files`, with a
  difference of 0.
- **SC-003**: 0 rows have an empty `venda_uuid`, and no two rows share one.
- **SC-004**: 100% of API sales join `tb_acesso` on `acesso_uuid`, apart from sales whose
  access `tb_acesso` dropped for the impossible address. Those are counted and explained.
- **SC-005**: 100% of sales join `tb_usuario` on `usuario_uuid`, apart from sales whose
  user `tb_usuario` dropped for sex. Those are counted and explained. 100% of sales carry
  one of the three course keys of the catalog.
- **SC-006**: 0 rows have an empty or negative `valor_pago`. 100% of files rows have
  `valor_desconto` = list price × discount and `valor_pago` = list price − discount.
- **SC-007**: 100% of rows have `percentual_desconto` in {`0%`, `5%`, `10%`, `15%`} and a
  non-empty `valor_desconto`.
- **SC-008**: 100% of rows have `origem` in {`API`, `ARQUIVO`} and a non-empty
  `data_carga`. `acesso_uuid` is empty exactly on the `ARQUIVO` rows, all of which have
  `pix` and `1` installment.
- **SC-009**: The quality view lists the five rules, each with failed counts equal to
  those computed directly from the sources.
- **SC-010**: A second run with no new data adds 0 rows.

## Assumptions

- `bronze_api` means the API events after validation: the valid side of feature 004.
  Reading bronze directly would skip the validation and the quarantine.
- `bronze_files` means `workspace.bronze.dados_files`, read through its boundary view, as
  in feature 006. The files source has no rejection rules, so it has no validation table
  or quarantine.
- A site sale is a valid event that carries a payment. In the generated data a payment
  exists exactly when a product exists.
- "uuid" means the constitution's `md5` hash key, not a random UUID.
- **Access key differs from the request's wording.** The request builds the access
  location as `Mobile` for iPhone and Android and `Computador` for everything else. The
  constitution requires one expression per key, and `tb_acesso` uses `unknown` for an
  unrecognized access point. The sale's access key therefore uses `tb_acesso`'s
  expression. With the request's version, sales from the 5% of events with an
  `unknown` access point would never join their access, which is the defect recorded in
  `doc/known-issues.md`.
- **`venda_uuid` is added.** The request does not list it. The constitution (Principle
  VI) requires a hash key on every conformed silver table. The business key columns in
  FR-006 are the defaults; planning verifies that they are unique in the current data.
- **`percentual_desconto` is spelled with "desconto".** The request writes
  `percentual_disconto`. Names are in Portuguese by the constitution, and the request
  already uses `valor_desconto`. The source fields keep their name `disconto`.
- **No discount gives `0%` and `0.00`.** The request's formulas would leave both empty
  for about 70% of API sales. A discount of zero is the true value, keeps the amount
  additive, and spares gold a special case for empty discounts.
- **Files installment value.** The request takes the files' `valor_parcelas` "from
  info_pagamento within the payload", but the files source has no payload. It is read as
  the list price minus the discount amount, a single `pix` installment, which is what the
  earlier pipeline intended.
- **API discount amount.** `valor_desconto` uses the list price in `info_produto`, as
  requested, not the paid amount in `info_pagamento.valor`, which already has the
  discount removed.
- The files `data_venda` is a date. As a timestamp it is midnight of that day.
- The request names no rule that removes rows, so all five rules only count. Every row of
  both sources reaches the table and reconciliation needs no exclusion.
- The API payment method keeps its source values (`credito`, `boleto`, `pix`). Events
  with `-----` are in quarantine.
- Sales are not deduplicated beyond the key. Each event and each file row is one sale.
- Gold (`fato_venda`, `dim_codigos`, `obt_acesso`) and the course table are out of scope.
- All data is synthetic.
