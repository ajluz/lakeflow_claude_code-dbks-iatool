# Feature Specification: Validation and Quarantine of API Events

**Feature Branch**: `004-api-quarantine`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "create the process to quarentine data on a quarentine table using the follow expectation rules: 1. CONSTRAINT curso_invalido = payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' 2. CONSTRAINT valor_invalido = payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00' 3. CONSTRAINT forma_pagamento_invalido = payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----' 4. partition it by fl_registro_invalido. It should be created throughout the temporary table workspace.silver.temp_tb_validacao_api. it will leed the pipeline to identify what record should be saved on quarentine table or should keep going downstream."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mark every API event as valid or invalid (Priority: P1)

As the project owner, I want every site event that arrives in bronze to pass once through a
validation step that marks it as valid or invalid, so that the rest of the pipeline can
decide where each event goes without repeating the rules.

The validation step is the pipeline-private table `workspace.silver.temp_tb_validacao_api`.
It holds every event from `workspace.bronze.dados_api`, read through the boundary view
`vw_bronze_dados_api` (which leaves out the bronze-only columns `source_file_name` and
`_rescued_data`), together with a flag, `fl_registro_invalido`, that is true when the event
breaks at least one rule.

An event is invalid when any of these holds:

| Rule | The event is invalid when | Null value in the field |
|---|---|---|
| `curso_invalido` | the product name is the placeholder `'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` (32 `x`) | passes |
| `valor_invalido` | the payment value is `'0.00'` | passes |
| `forma_pagamento_invalido` | the payment method is the placeholder `'-----'` | passes |
The three rules come from the request. Under constitution v1.6.0, rescued data is not
checked in silver: it stays visible only in bronze.

**Why this priority**: nothing can be quarantined or sent downstream until each event is
classified. The flag is the single decision point of the whole split.

**Independent Test**: load a set of bronze events in which some carry each placeholder,
some carry none, and some have no payload. Run the pipeline and confirm the validation
table has exactly as many rows as bronze, and that the flag is true exactly on the events
that break a rule.

**Acceptance Scenarios**:

1. **Given** an event whose product name is the 32-`x` placeholder, **When** it is
   validated, **Then** its flag is true.
2. **Given** an event whose payment value is `'0.00'`, **When** it is validated, **Then**
   its flag is true.
3. **Given** an event whose payment method is `'-----'`, **When** it is validated, **Then**
   its flag is true.
4. **Given** an event with no payload, or with a payload whose product and payment fields
   are empty, **When** it is validated, **Then** its flag is false.
5. **Given** an event with a real product name, a non-zero value and a real payment method,
   **When** it is validated, **Then** its flag is false.
6. **Given** any run, **When** the validation table is compared with
   `workspace.bronze.dados_api`, **Then** it holds the same number of rows: validation adds
   a flag but removes nothing.
7. **Given** the validation table, **When** its physical layout is inspected, **Then** it is
   partitioned by `fl_registro_invalido`.

---

### User Story 2 - Count every rule violation in the pipeline's quality metrics (Priority: P1)

As the project owner, I want each of the rules to appear by name in the pipeline's data
quality view, with how many events passed and failed it, so that I can show in the talk how
much bad data arrives and which rule catches it.

The rules are declared on the validation table as expectations that only measure: an event
that breaks a rule is counted, but it stays in the table so it can be routed to quarantine.

**Why this priority**: the constitution makes measured rules non-negotiable, and the
quality metrics are the visible part of the demonstration. A rule that is not measured
cannot be audited.

**Independent Test**: after a run on the test set from User Story 1, open the data quality
view of the validation table and confirm that each rule appears by its name and that its
failed count equals the number of test events built to break it.

**Acceptance Scenarios**:

1. **Given** a completed run, **When** the quality view of the validation table is opened,
   **Then** it lists `curso_invalido`, `valor_invalido` and `forma_pagamento_invalido`.
2. **Given** a known number of events that break one rule, **When** the run completes,
   **Then** that rule's failed count equals that number.
3. **Given** events that break a rule, **When** the run completes, **Then** none of them is
   dropped from the validation table and the run does not stop.
4. **Given** any event, **When** the flag and the rules are compared, **Then** the flag is
   true if and only if at least one rule failed for that event.

---

### User Story 3 - Keep invalid events in a quarantine table (Priority: P1)

As the project owner, I want every invalid event to be saved, unchanged, in a quarantine
table in silver, together with the names of the rules it broke, so that bad data is never
silently lost and can be inspected or reprocessed after the cause is fixed.

**Why this priority**: this is the outcome the request asks for. Without it, invalid events
would exist only in bronze and the counts could not be reconciled.

**Independent Test**: after a run on the test set, query the quarantine table and confirm
it holds exactly the events whose flag is true, with their original content and the rules
each one broke.

**Acceptance Scenarios**:

1. **Given** an event with its flag true, **When** the run completes, **Then** it is in the
   quarantine table exactly once.
2. **Given** an event with its flag false, **When** the run completes, **Then** it is not in
   the quarantine table.
3. **Given** a quarantined event, **When** it is compared with its bronze row, **Then**
   every field the boundary view delivers, including the nested payload and
   `processing_time`, has the same value, and `source_file_name` and `_rescued_data` are
   absent.
4. **Given** a quarantined event that broke two rules, **When** it is read, **Then** both
   rule names are recorded on it.
5. **Given** a quarantined event, **When** it is read, **Then** it carries every column of
   the validation table, including the flag and the validation time, states that it came
   from the `API` source, and states when it was loaded into quarantine.
6. **Given** a completed run followed by a run with no new events, **When** the quarantine
   table is counted, **Then** it has not grown.

---

### User Story 4 - Let valid events continue downstream (Priority: P2)

As the project owner, I want the valid events to be available to the conformed silver
tables, and only those, so that the conformed tables are clean without each one restating
the rules.

**Why this priority**: the conformed tables are built in a later feature. This feature
must leave the valid side of the split ready and unambiguous for them, but delivers its
value even before they exist.

**Independent Test**: query the validation table for events whose flag is false and
confirm that, added to the quarantine count, they equal the bronze count, and that none of
them is in quarantine.

**Acceptance Scenarios**:

1. **Given** a completed run, **When** the counts are compared, **Then** bronze events
   equal valid events plus quarantined events.
2. **Given** an event, **When** it is classified, **Then** it is either valid or
   quarantined, never both and never neither.
3. **Given** the project documentation, **When** a later feature builds a conformed table
   from API events, **Then** the documentation states that it must read only events whose
   flag is false.

---

### Edge Cases

- An event has no payload at all (a visit without a purchase): every field the rules look
  at is empty, so every rule passes and the event is valid.
- An event has a product but no payment, or a payment but no product: only the rules on the
  present fields can fail.
- The product name differs from the placeholder only in case or length (for example 31
  `x`): it is not the placeholder and the rule passes. Only the exact value is rejected.
- The payment value is zero written another way: the comparison is with the value
  `0.00` given in the request, as the field's own type reads it. If the field holds
  numbers, every zero amount equals `0.00` and is rejected. If it holds text, only the exact
  text `'0.00'` is rejected, and `'0'`, `'0,00'` or `'R$ 0,00'` pass.
- An event breaks all three content rules: it is quarantined once, with all three rule
  names.
- A bronze event carries rescued data: silver does not see it. The event is classified by
  the three content rules only; its rescued content stays in bronze.
- The same event is delivered twice in bronze (a file re-delivered): each bronze row is
  validated and routed on its own. Deduplication is not done here.
- A run receives no new events: the validation and quarantine tables gain no rows.
- A rule is changed later: the flag and the expectation for that rule must change
  together, and events already validated are not re-evaluated unless the owner approves a
  full refresh.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a validation table
  `workspace.silver.temp_tb_validacao_api`, private to the pipeline, fed incrementally from
  `workspace.bronze.dados_api` through the boundary view `vw_bronze_dados_api`.
- **FR-002**: The validation table MUST hold every bronze event, with every column the
  boundary view delivers unchanged, and MUST NOT drop, filter, deduplicate or alter any
  event.
- **FR-002a**: The boundary view MUST deliver every bronze column except `source_file_name`
  and `_rescued_data`, and MUST NOT filter, cast, rename or apply rules. Neither silver
  table may carry those two columns (constitution v1.6.0, Principle I).
- **FR-003**: The validation table MUST add a true/false column `fl_registro_invalido`
  that is true when at least one rule in FR-004 fails, and false otherwise. It MUST never be
  empty.
- **FR-004**: The rules MUST be exactly these, each passing when its field is empty:

  | Name | Passes when |
  |---|---|
  | `curso_invalido` | `payload.info_produto.product_name` is empty or is not `'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` |
  | `valor_invalido` | `payload.info_pagamento.valor` is empty or is not `'0.00'` |
  | `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento` is empty or is not `'-----'` |

- **FR-005**: Each rule in FR-004 MUST be declared on the validation table as a named
  quality expectation that measures without removing rows or stopping the run.
- **FR-006**: The flag and the expectations MUST encode the same predicates, so that the
  flag is true for an event if and only if at least one expectation fails for it.
- **FR-007**: The validation table MUST record, for each event, which rules it broke.
- **FR-008**: The validation table MUST be partitioned by `fl_registro_invalido`, so that
  reading only the valid or only the invalid events reads only their partition.
- **FR-009**: The feature MUST provide a quarantine table in silver, fed incrementally from
  the validation table, holding every event whose flag is true and no other.
- **FR-010**: A quarantine row MUST preserve the event as delivered by the boundary view,
  without transformation: every column of the view, nested payload included, with its
  original value.
- **FR-011**: A quarantine row MUST record the names of the rules that rejected it.
- **FR-012**: The validation and quarantine tables MUST carry `origem` with the literal
  value `API` and `data_carga` with the time the row was validated. The quarantine table
  MUST also carry `data_carga_quarentena`, the time the row entered quarantine.
- **FR-012a**: The quarantine table MUST carry every column of the validation table, with
  nothing excluded or replaced: the delivered event, `regras_violadas`,
  `fl_registro_invalido`, `origem` and `data_carga`. All the evidence of a data issue is
  then in one row (constitution v1.6.0, Principle IV; owner, 2026-10-18).
- **FR-013**: For each run, the number of bronze API events MUST equal the number of valid
  events plus the number of quarantined events.
- **FR-014**: Events whose flag is false MUST remain available in the validation table for
  the conformed silver tables, and the documentation MUST state that conformed tables read
  only those events.
- **FR-015**: Events already validated or quarantined MUST NOT be processed again by a
  later run.
- **FR-016**: Both tables MUST carry the table property `quality` with the value `silver`.
- **FR-017**: The definitions MUST be written in SQL, in the current syntax of Lakeflow
  Spark Declarative Pipelines, one file per dataset, named `NN_<dataset>.sql` and numbered
  from `01` in the silver folder of the pipeline source (constitution v1.6.0).
- **FR-017a**: The bronze definition files MUST be renamed with the same numbering
  (`01_dados_api.sql`, `02_dados_files.sql`, `03_dados_database.sql`), with no change to
  their content.
- **FR-018**: The validation table, the quarantine table, the rules and the flag MUST be
  described in the project documentation, replacing the descriptions of the earlier
  pipeline.

### Key Entities

- **API event**: one site visit from `workspace.bronze.dados_api`, with access time,
  address, device, an optional nested payload (user, product, payment) and
  `processing_time`. Its bronze-only columns `source_file_name` and `_rescued_data` stop at
  the boundary view.
- **Boundary view** (`vw_bronze_dados_api`): the API events as silver may see them: every
  bronze column except `source_file_name` and `_rescued_data`. Pipeline-scoped, not
  persisted.
- **Validation rule**: a named condition an event must meet. Three exist (FR-004). Each is
  both a measured expectation and part of the flag.
- **Validation table** (`temp_tb_validacao_api`): every API event plus its flag, the names
  of the rules it broke, its record source and its load time. Private to the pipeline.
- **Invalid-record flag** (`fl_registro_invalido`): true when the event broke at least one
  rule. The only thing downstream tables use to choose their side of the split.
- **Quarantine table**: the invalid events with every column of the validation table: the
  event unchanged, the rules each one broke, the flag, its record source and validation
  time, plus the time it entered quarantine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a run, the validation table holds 100% of bronze API events, and 0
  events are lost or duplicated.
- **SC-002**: On a test set built to cover each rule, 100% of events built to break a rule
  have the flag true and 100% of the others have it false.
- **SC-003**: The quality view lists all 3 rules by name, and each rule's failed count
  equals the number of test events built to break it.
- **SC-004**: Bronze events = valid events + quarantined events, with a difference of 0,
  for every run.
- **SC-005**: 100% of quarantined events match their bronze row field for field, apart
  from the two excluded lineage columns, and name at least one rule.
- **SC-006**: 100% of rows in both tables have `origem` = `API` and a non-empty
  `data_carga`.
- **SC-007**: A second run with no new bronze events adds 0 rows to either table.
- **SC-008**: The owner can show, in a single run of the pipeline, how many events were
  rejected by each rule and inspect each rejected event, without editing any definition.

## Assumptions

- Each constraint in the request is the condition a valid event meets; its name (for
  example `curso_invalido`) is the name under which a failure is counted. The flag is true
  when any of them fails.
- An empty product name passes `curso_invalido`, the same way empty fields pass the other
  two rules. The request writes this rule without the empty case, but the payload is
  optional (visits without a purchase are normal), and the earlier pipeline's
  documentation states the same behavior.
- "Partition it by fl_registro_invalido" is met by partitioning on the flag. Clustering was
  chosen first (2026-10-18), but the platform rejects it:
  `DELTA_CLUSTERING_COLUMNS_DATATYPE_NOT_SUPPORTED`, because a `BOOLEAN` column does not
  support data skipping. The owner then decided to partition, as originally requested.
  Constitution Principle V forbids `PARTITIONED BY` on new datasets, so this is a recorded
  exception in the plan's Complexity Tracking.
- The placeholders are matched exactly as written in the request, as text. No other
  spellings of zero or of an empty payment method are rejected.
- A fourth rule on rescued data was planned under constitution v1.5.0 and removed when the
  owner amended it to v1.6.0 (2026-10-18). Rescued content stays visible only in bronze.
- The quarantine table is named `workspace.silver.tb_quarentena`, the name the project
  documentation already uses. Only the API source is quarantined in this feature; if the
  other sources are quarantined later and differ in shape, the constitution's
  `tb_quarentena_<source>` naming applies to them.
- The validation table reads bronze through the boundary view `vw_bronze_dados_api`,
  which the constitution (v1.6.0) requires before each zone change.
- Conformed silver tables (access, users, sales) and the gold layer are out of scope. They
  are later features and read the valid side of the split.
- Reprocessing quarantined events after a fix is out of scope; the quarantine table makes
  it possible but no replay process is built here.
- Bronze `dados_api` exists and is populated (feature 003). Test events that break each
  rule may need to be generated; if the generator does not produce them, building that test
  set is part of validating this feature.
- The environment is Databricks Free Edition with serverless pipelines. All data is
  synthetic.
