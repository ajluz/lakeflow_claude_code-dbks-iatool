# Research: Validation and Quarantine of API Events

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18 (revised for constitution v1.6.0)

Sources consulted: the `databricks-pipelines` skill (`SKILL.md`,
`references/streaming-table-sql.md`, `references/expectations-sql.md`), the Databricks
reference page for `CREATE STREAMING TABLE` in pipelines, constitution v1.5.0 and its
amendment v1.6.0 (2026-10-18), `references/temporary-view-sql.md`, the bronze
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
| Type of `payload.info_pagamento.valor` in bronze | **DOUBLE** (confirmed 2026-10-18, T004) | `typeof()` on bronze; see Decision 4 |

## Decision 1: The validation table reads bronze through the boundary view `vw_bronze_dados_api`

- **Decision**: a temporary view `vw_bronze_dados_api`, defined as
  `SELECT * EXCEPT (source_file_name, _rescued_data) FROM STREAM(workspace.bronze.dados_api)`.
  `temp_tb_validacao_api` reads `STREAM(vw_bronze_dados_api)`.
- **Rationale**: constitution v1.6.0 (Principle I) requires every read across a zone
  boundary to go through a temporary view that excludes the bronze-only lineage columns,
  and forbids silver tables from carrying them. The owner amended the constitution to
  require this on 2026-10-18, matching the earlier pipeline's `vw_bronze_dados_api`.
  `processing_time` is kept: the amendment does not exclude it.
- **Revision**: the first design (v1.5.0) read bronze directly. That kept `_rescued_data`
  so that a fourth rule could quarantine rescued records, as v1.5.0 required. v1.6.0
  removed that requirement, so the view no longer costs anything Principle IV needs.
- **Name**: unqualified. Temporary views are pipeline-scoped and not persisted (skill,
  `temporary-view-sql.md`), and the constitution's three-level-name rule covers
  persisted datasets.
- **Alternatives considered**: computing a rescued-data flag in the view so that the
  fourth rule could survive. Rejected by the owner (2026-10-18). A view that also adds
  `origem` was rejected because the constitution allows the boundary view to do nothing
  but exclude the two columns.

## Decision 2: Private streaming table, three-level name, partitioned by the flag

- **Decision**:
  `CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api (...) PARTITIONED BY (fl_registro_invalido)`.
- **Rationale**: Principle IV calls for a private validation table, and Principle V
  allows a private streaming table here because it is the materialized split point that
  both quarantine and the later conformed tables read. Bronze grows incrementally, so the
  table is a streaming table.
- **Layout, revised 2026-10-18**: clustering on the flag (option A) was planned first,
  because Principle V forbids `PARTITIONED BY` and prescribes `CLUSTER BY`. The first real
  update rejected it: `[DELTA_CLUSTERING_COLUMNS_DATATYPE_NOT_SUPPORTED] CLUSTER BY is not
  supported because the following column(s): fl_registro_invalido : BOOLEAN don't support
  data skipping.` Liquid clustering needs columns that carry min/max statistics for data
  skipping, and `BOOLEAN` does not. The validate-only run did not catch this, because it
  does not create tables. The owner then decided to partition by the flag, as the request
  originally said. This is a deviation from Principle V, justified in the plan's Complexity
  Tracking. Two partitions (`true`, `false`) is the safe case for partitioning: no
  small-file or over-partitioning risk.
- **Naming**: the reference page says a private table's "fully qualified table name must be
  unique", that it "can have the same name as an existing object in the catalog", and that
  references to the name inside the pipeline resolve to the private table. A three-level
  name is therefore expected to work. The constitution requires one, and the request names
  `workspace.silver.temp_tb_validacao_api`.
- **Risk and fallback**: the reference does not show a qualified private name
  explicitly. The dry run (`--validate-only`) is the check. If it rejects the qualified
  name, the implementer stops and reports to the owner rather than silently dropping the
  qualifier, because an unqualified name would fall into the pipeline's default schema,
  `bronze`. The validate-only run of 2026-10-18 accepted it.
- **Consequence**: a private table is not in the catalog, so it cannot be queried from
  outside the pipeline. Validation of its contents uses the pipeline event log (row counts
  and expectation metrics) and the published quarantine table. See
  [quickstart.md](quickstart.md).
- **Alternatives considered**: a published streaming table. Rejected: it would expose an
  internal staging table and contradict Principle IV's "private validation table". A
  temporary view. Rejected: it cannot carry `CONSTRAINT` clauses (Principle III), and the
  rule metrics belong on the validation step.

## Decision 3: The predicates are null-safe, and the rules are written as the request gives them

- **Decision**: the three expectations, all warn-only (no `ON VIOLATION`):

  | Name | Condition (passes when true) |
  |---|---|
  | `curso_invalido` | `payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'` |
  | `valor_invalido` | `payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00'` |
  | `forma_pagamento_invalido` | `payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----'` |

  A fourth rule, `registro_nao_conforme` (`_rescued_data IS NULL`), was part of the design
  under v1.5.0 and was removed with the amendment to v1.6.0.

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
  failed rule, from the same three conditions in the same order as the `CONSTRAINT`
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
  - Three Boolean columns in a temporary view upstream, read by both the flag and the
    expectations. Rejected: an extra dataset and three extra columns that would be carried
    into quarantine.

## Decision 6: The quarantine table is a published streaming table that filters on the flag

- **Decision**: `workspace.silver.tb_quarentena`, a streaming table reading
  `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE fl_registro_invalido`. It
  keeps every column of the validation table (`*`, nothing excluded or replaced) and adds
  `data_carga_quarentena`.
- **Rationale**: Principle IV names `tb_quarentena`, and only the API source is quarantined
  in this feature. The `WHERE` is a routing filter, not a quality rule: the rules are
  measured on the validation table. Keeping every column, including the flag and the
  validation `data_carga`, puts all the evidence of a data issue in one row, so nobody has
  to join back to the private validation table, which cannot be queried outside the
  pipeline. The owner set this as a constitution rule on 2026-10-18 (Principle IV). The
  first design dropped the flag and replaced `data_carga`; it was revised before any
  quarantine row existed.
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

- **Decision**: three files in `src/pipeline/02_silver/`, numbered per constitution v1.6.0:
  `01_vw_bronze_dados_api.sql`, `02_temp_tb_validacao_api.sql`, `03_tb_quarentena.sql`.
  The bronze files are renamed to `01_dados_api.sql`, `02_dados_files.sql` and
  `03_dados_database.sql`, with content unchanged, in the order of feature 003's contract.
  Each file holds one statement, with no `CREATE FLOW`.
- **Rationale**: Principle V (v1.6.0) names files `NN_<dataset>.sql`, numbered from `01`
  per zone folder in reading order. The numbers follow the data flow: view, validation,
  quarantine. A single-source streaming table needs no explicit flow (skill,
  `streaming-table-sql.md`). Comments are in Portuguese, as in the bronze files.
- **Workspace consequence**: `import-dir --overwrite` adds and replaces files but deletes
  none. The old unnumbered files in the workspace (three in `01_bronze/`, and
  `02_silver/temp_tb_validacao_api.sql`) must be deleted after the upload. Otherwise the
  pipeline would see each dataset defined twice.

## Decision 8: Rollout, and the empty table left by the first attempt

- **Decision**: upload the new files, delete the old ones in the workspace, and run a
  normal update.
- **State found on 2026-10-18**: the owner's update of 14:39 UTC created the private
  table's backing table (`workspace.silver.__8d51ac7a_..._temp_tb_validacao_api`) with the
  v1.5.0 column set, before failing on `CLUSTER BY`. It holds no rows: the next update was
  cancelled before the silver flow ran. `tb_quarentena` has never been created.
- **Consequence**: the new definition drops `source_file_name` and `_rescued_data` and
  changes the layout. If the normal update refuses that schema change, the fix is a
  refresh of `temp_tb_validacao_api` only (`full_refresh_selection`). It loses nothing,
  because the table is empty, but the constitution requires the owner's approval first.
- **Rationale**: the constitution forbids a routine full refresh. Beyond the case above,
  one is needed only if a rule changes later and the owner wants old events
  re-evaluated, as the spec's edge cases already state.
