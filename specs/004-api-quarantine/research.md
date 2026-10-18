# Research: Validation and Quarantine of API Events

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

Sources consulted: the `databricks-pipelines` skill (`SKILL.md`,
`references/streaming-table-sql.md`, `references/expectations-sql.md`), the Databricks
reference page for `CREATE STREAMING TABLE` in pipelines, constitution v1.5.0, the bronze
design of feature 003 (`specs/003-bronze-ingestion/data-model.md`), the generator in
`explorations/functions.py`, and the description of the earlier pipeline in
`doc/pipeline-reference.md` and `doc/architecture.md`.

## Facts established

| Fact | Value | Source |
|---|---|---|
| Bronze source | `workspace.bronze.dados_api`, streaming table, append-only | feature 003 |
| Bronze columns | `processing_time`, `source_file_name`, `access_date`, `access_point`, `ip_address`, `payload`, `_rescued_data` | 003 data-model |
| Field paths of the rules | `payload.info_produto.product_name`, `payload.info_pagamento.valor`, `payload.info_pagamento.forma_pagamento` | 003 data-model |
| The generator produces the placeholders | product `'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'`, course price `0.00` (weight 4 of 100), payment method `'-----'` | `explorations/functions.py` lines 23, 27–28, 39 |
| Rescued records in bronze today | 0 | 003 research |
| Pipeline source path | glob `.../lakeflow_dev/src/pipeline/**`; a new `02_silver/` folder is picked up without changing settings | `explorations/setup/03_pipeline_dev.json` |
| Pipeline default schema | `bronze`; every dataset here is named by three-level name, so the default does not matter | same |
| Type of `payload.info_pagamento.valor` in bronze | **to confirm at implementation**. The generator writes it as `DECIMAL(9,2)`, and JSON inference normally reads such numbers as `DOUBLE` | generator schema; see Decision 4 |

## Decision 1: The validation table reads bronze directly, with no intermediate view

- **Decision**: `temp_tb_validacao_api` reads `STREAM(workspace.bronze.dados_api)` and
  selects `*`, so every bronze column reaches validation and quarantine unchanged.
- **Rationale**: a quarantine row must preserve the original record (Principle IV,
  FR-010), and rows with `_rescued_data` must be routed to quarantine. The earlier
  pipeline's view `vw_bronze_dados_api` dropped `source_file_name` and `_rescued_data`
  before validation, which breaks both rules. Nothing needs reshaping before validation,
  so a view would add a node to the graph with nothing to do.
- **Alternatives considered**: a temporary view `vw_bronze_dados_api` that adds `origem`.
  Rejected: one literal column does not justify a dataset, and the validation table is the
  first dataset of the source in silver, which is where the constitution places `origem`.

## Decision 2: Private streaming table, three-level name, clustered on the flag

- **Decision**:
  `CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api (...) CLUSTER BY (fl_registro_invalido)`.
- **Rationale**: Principle IV calls for a private validation table, and Principle V
  allows a private streaming table here because it is the materialized split point that
  both quarantine and the later conformed tables read. Bronze grows incrementally, so the
  table is a streaming table. Clustering on the flag is the owner's choice (option A,
  2026-10-18) and follows Principle V, which forbids `PARTITIONED BY`. The skill marks
  `CLUSTER BY` as liquid clustering, mutually exclusive with partitioning.
- **Naming**: the reference page says a private table's "fully qualified table name must be
  unique", that it "can have the same name as an existing object in the catalog", and that
  references to the name inside the pipeline resolve to the private table. A three-level
  name is therefore expected to work. The constitution requires one, and the request names
  `workspace.silver.temp_tb_validacao_api`.
- **Risk and fallback**: the reference does not show a qualified private name or
  `CLUSTER BY` on a private table explicitly. The dry run (`--validate-only`) is the check.
  If it rejects the qualified name, the implementer stops and reports to the owner rather
  than silently dropping the qualifier, because an unqualified name would fall into the
  pipeline's default schema, `bronze`. If it rejects `CLUSTER BY` on a private table, the
  implementer reports that too; partitioning is not a fallback.
- **Consequence**: a private table is not in the catalog, so it cannot be queried from
  outside the pipeline. Validation of its contents uses the pipeline event log (row counts
  and expectation metrics) and the published quarantine table. See
  [quickstart.md](quickstart.md).
- **Alternatives considered**: a published streaming table. Rejected: it would expose an
  internal staging table and contradict Principle IV's "private validation table". A
  temporary view. Rejected: it cannot carry `CONSTRAINT` clauses (Principle III), and the
  rule metrics belong on the validation step.

## Decision 3: The predicates are null-safe, and the rules are written as the request gives them

- **Decision**: the four expectations, all warn-only (no `ON VIOLATION`):

  | Name | Condition (passes when true) |
  |---|---|
  | `curso_invalido` | `payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` |
  | `valor_invalido` | `payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00'` |
  | `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----'` |
  | `registro_nao_conforme` | `_rescued_data IS NULL` |

- **Rationale**: Principle III requires every condition to state how it treats `NULL`. The
  reference page does not say how a `NULL` condition result is counted, so the conditions
  are written so that they can never be `NULL`: each one is `IS NULL OR <comparison>`, and
  the comparison is evaluated only when the field is present. A missing `payload`,
  `info_produto` or `info_pagamento` makes the nested field `NULL`, so a visit without a
  purchase passes. Rule 1 gains the `IS NULL OR` the request left out, as the spec's
  assumptions decided. Rules 2 and 3 are the request's text unchanged.
- **Alternatives considered**: the request's rule 1 without the null branch. Rejected: its
  result is `NULL` for every visit without a product, and how such rows are counted is
  undocumented.

## Decision 4: The comparison with `'0.00'` follows the column's type

- **Decision**: keep the literal `'0.00'` from the request.
- **Rationale**: if bronze inferred `valor` as `DOUBLE` or `DECIMAL`, the string literal is
  cast to the column's type and the comparison is numeric: every zero amount is rejected,
  which is the intent of the generator's `0.00` price. If bronze inferred `STRING`, the
  comparison is textual and matches the generator's output for a zero price only if it
  was written as `0.00`. The spec's edge case covers both readings.
- **To confirm at implementation**: read the type with
  `DESCRIBE TABLE workspace.bronze.dados_api` and count the rows the rule rejects
  ([quickstart.md](quickstart.md), step 1). If the count is 0 while the generator produced
  zero-price sales, report it to the owner before going further. Do not change the literal
  on your own.

## Decision 5: Each rule is written once in the flag and once in its expectation

- **Decision**: the select list builds `regras_violadas`, an array with the name of each
  failed rule, from the same four conditions in the same order as the `CONSTRAINT`
  clauses. Then `fl_registro_invalido = size(regras_violadas) > 0`.
- **Rationale**: Principle IV requires the flag and the expectations to encode the same
  predicates, and the quarantine row to record which rules rejected it (FR-007, FR-011).
  Building the array first and deriving the flag from it means the flag cannot disagree
  with the list of rules. The conditions are written literally in the `CONSTRAINT` clauses
  because that is how the request states them and how the talk shows them. In the array,
  each condition sits on its own line, next to its rule name, so that a reviewer can
  compare the two lists line by line.
- **Mechanism**: `filter(array(CASE WHEN NOT (<cond>) THEN '<name>' END, ...), r -> r IS NOT NULL)`.
  Because no condition can be `NULL` (Decision 3), `NOT (<cond>)` is always true or false
  and the flag is never `NULL` (FR-003).
- **Verification**: the quickstart compares, for each rule, the expectation's failed count
  in the event log with the number of quarantine rows whose `regras_violadas` contains that
  rule. A mismatch means the two lists drifted.
- **Alternatives considered**:
  - Expectations that read the array, for example
    `EXPECT (NOT array_contains(regras_violadas, 'curso_invalido'))`. Rejected: each
    predicate would be written only once, but the rule would no longer be visible in the
    expectation, and the request asks for the rules as constraints.
  - Four Boolean columns in a temporary view upstream, read by both the flag and the
    expectations. Rejected: an extra dataset and four extra columns that would be carried
    into quarantine.

## Decision 6: The quarantine table is a published streaming table that filters on the flag

- **Decision**: `workspace.silver.tb_quarentena`, a streaming table reading
  `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE fl_registro_invalido`. It
  keeps every bronze column, `regras_violadas` and `origem`, takes a new `data_carga`, and
  does not carry the flag, which is always true there.
- **Rationale**: Principle IV names `tb_quarentena`, and only the API source is quarantined
  in this feature. The `WHERE` is a routing filter, not a quality rule: the rules are
  measured on the validation table. `data_carga` is the time the row entered quarantine
  (spec, User Story 3 scenario 5).
- **Expectation on quarantine**: Principle III requires at least one expectation on every
  silver table. The quarantine table declares the warn expectation
  `regra_violada_registrada`: `size(regras_violadas) > 0`. It checks FR-011, that every
  quarantined row names at least one rule. It is never `NULL`, because `filter` over a
  non-null array returns an array.
- **Hash key**: Principle VI requires hash keys on conformed silver tables. Quarantine is
  not conformed: it holds rejected records unchanged. Completion gate 4 ("unless exempted
  by Principle VI") therefore asks only for `origem` here.
- **Alternatives considered**: `tb_quarentena_api`. Kept for later: the constitution
  requires the source suffix only when sources of different shapes share quarantine, and
  only one source is quarantined now. The spec records this choice.

## Decision 7: Files, folder and naming

- **Decision**: `src/pipeline/02_silver/temp_tb_validacao_api.sql` and
  `src/pipeline/02_silver/tb_quarentena.sql`. Each holds one `CREATE OR REFRESH ... AS
  SELECT`, with no `CREATE FLOW`.
- **Rationale**: the constitution's repository layout names `02_silver/`. Principle V
  requires one file per dataset, named after it. A single-source streaming table needs no
  explicit flow (skill, `streaming-table-sql.md`). Comments are in Portuguese, as in the
  bronze files.

## Decision 8: Rollout without a full refresh

- **Decision**: upload the new files and run a normal update. Both tables are new, so on
  their first update they read bronze from the beginning. No existing table changes.
- **Rationale**: the constitution forbids a routine full refresh. It is needed only if a
  rule changes later and the owner wants old events re-evaluated, which the spec's edge
  cases already state.
