# Data's Light Academy Lakeflow Constitution

## Core Principles

### I. Medallion Architecture

Every dataset belongs to exactly one layer, and data moves only forward through them.

- **Bronze** (`workspace.bronze`) holds source data as it arrived. Bronze tables MUST be
  append-only streaming tables, MUST keep every source column, and MUST add only lineage
  columns (`processing_time`, `source_file_name`) and Auto Loader's `_rescued_data`. Bronze
  MUST NOT filter, cast, rename, deduplicate, or drop rows.
- **Silver** (`workspace.silver`) holds validated, typed, conformed data. All cleansing,
  casting, key derivation, validation, and merging of sources happens here.
- **Gold** (`workspace.gold`) holds the analytics model: dimensions, facts, and
  denormalized tables. Gold MUST read from silver or from other gold datasets. Reading
  bronze from gold is a violation unless the Complexity Tracking section of the plan
  justifies it.
- A dataset MUST NOT read from a later layer, and a layer MUST NOT be skipped.
- Every persisted table MUST carry `TBLPROPERTIES ("quality" = "<layer>")`.
- Every dataset the pipeline reads MUST be defined in the pipeline. The only exception is
  static reference data (for example the calendar dimension), which MUST be loaded by an
  idempotent script and listed in `doc/pipeline-reference.md`.
- Gold facts MUST reconcile with silver: a join to a dimension MUST NOT silently remove
  fact rows. Unmatched or not-applicable lookups MUST resolve to an explicit default
  member, and any intended exclusion MUST be documented.

**Rationale**: a fixed direction of flow keeps raw data replayable, puts every business
rule in one findable place, and makes a row count at one layer explainable from the layer
before it.

### II. SQL-Only Declarative Pipelines

All transformation logic is expressed as Lakeflow Spark Declarative Pipelines datasets
written in SQL.

- Pipeline source MUST be `.sql` files. Python, Scala, notebooks, and imperative
  statements (`MERGE`, `INSERT`, `UPDATE`, `DELETE` outside a `CREATE FLOW`) MUST NOT be
  used to build bronze, silver, or gold datasets.
- A requirement that only the Python API can meet (sinks, snapshot CDC, custom data
  sources, Python UDFs) MUST be redesigned in SQL or raised as a constitution amendment.
  It MUST NOT be worked around inside the pipeline.
- Datasets MUST be declared, never orchestrated. Execution order comes from dependencies
  between datasets; numeric file prefixes are for reading order only.
- Code MUST use current syntax: `CREATE OR REFRESH STREAMING TABLE`,
  `CREATE OR REFRESH MATERIALIZED VIEW`, `CREATE TEMPORARY VIEW`,
  `CREATE OR REFRESH PRIVATE ...`, `STREAM read_files(...)`, `STREAM(name)`,
  `CREATE FLOW ... AS INSERT INTO`, and `CREATE FLOW ... AS AUTO CDC INTO`.
- Legacy Delta Live Tables syntax MUST NOT be added and MUST be migrated when a file is
  touched: `LIVE TABLE`, `STREAMING LIVE TABLE`, `TEMPORARY LIVE VIEW`, the `LIVE.` prefix,
  `cloud_files(...)`, `APPLY CHANGES INTO`, and `input_file_name()`. `CREATE OR REPLACE`
  MUST NOT be used for pipeline datasets.
- Python is permitted only outside the pipeline, for synthetic data generation and
  exploration under `explorations/`.

**Rationale**: one language and one execution model keep the project teachable and
reviewable, and let the platform own ordering, retries, incremental state, and lineage.

### III. Data Quality Through Expectations (NON-NEGOTIABLE)

Every data quality rule is a named Databricks expectation, so that its outcome is measured
by the pipeline.

- A quality rule MUST be declared as `CONSTRAINT <name> EXPECT (<condition>)` on a
  streaming table or materialized view. A bare `WHERE` filter MUST NOT be the only
  expression of a quality rule, because it leaves no metric.
- Every silver table MUST declare at least one expectation. A silver table with none MUST
  state why in its plan.
- Each expectation MUST choose its action deliberately:
  - **Warn** (no `ON VIOLATION`): measure a rule without removing rows.
  - **`ON VIOLATION DROP ROW`**: remove rows, subject to Principle IV.
  - **`ON VIOLATION FAIL UPDATE`**: stop the update. Reserved for invariants whose
    violation would make downstream data wrong, such as a null or duplicated key in a gold
    dimension.
- Constraint names MUST be unique within a dataset and MUST describe what is validated.
- Conditions MUST be simple row-level SQL Boolean expressions: no subqueries, no UDFs, no
  external calls. A condition MUST state how it treats `NULL`.
- Bronze tables MUST NOT declare `DROP ROW` or `FAIL UPDATE` expectations.
- Expectations go on persisted datasets. `CREATE TEMPORARY VIEW` does not accept
  `CONSTRAINT` clauses, so a rule is attached to the streaming table or materialized view
  downstream of the view.

**Rationale**: expectations publish pass and fail counts to the pipeline's data quality tab
and event log. A rule that is not an expectation is invisible, and an invisible rule
cannot be trusted or audited.

### IV. Quarantine, Never Silently Discard

A record rejected by a quality rule is kept, unchanged, where it can be inspected and
replayed.

- Validation of a source happens once, at the bronze-to-silver boundary, in a private
  validation table that adds a Boolean flag column (`fl_registro_invalido`) computed from
  the rejection rules.
- The same rules MUST also be declared on that validation table as warn expectations, so
  that every rejection is counted. The flag and the expectations MUST encode the same
  predicates; changing one without the other is a violation.
- Flagged rows MUST be written to a quarantine streaming table in silver
  (`tb_quarentena`, or `tb_quarentena_<source>` when sources differ in shape). Conformed
  silver tables MUST read only rows where the flag is false.
- A quarantine row MUST preserve the original record without transformation, and MUST
  record which rule or rules rejected it.
- `ON VIOLATION DROP ROW` is permitted only when the dropped rows are also routed to a
  quarantine table by the same predicate. Dropping a row that exists nowhere but bronze is
  a violation.
- Rows whose `_rescued_data` is not null MUST be routed to quarantine. `_rescued_data`
  MUST NOT be discarded before that check.
- For each source, rows in bronze MUST equal rows conformed plus rows quarantined, apart
  from exclusions documented in `doc/pipeline-reference.md`.

**Rationale**: dropping bad data hides upstream defects and makes totals impossible to
reconcile. Quarantine keeps the conformed flow clean while preserving the evidence and the
option to reprocess once the cause is fixed.

### V. Dataset Types and Flows That Fit the Source

The dataset type follows from the nature of the source, not from habit.

- A source that grows incrementally (files in a volume, another streaming table) MUST feed
  a **streaming table** read with `STREAM(...)`.
- A full-scan result (joins across tables, aggregations, gold facts and denormalized
  tables) MUST be a **materialized view** read without `STREAM`.
- Intermediate logic MUST default to a **temporary view**. A private streaming table or
  private materialized view is allowed only when materializing once avoids significant
  reprocessing, as with the validation table in Principle IV.
- File ingestion MUST use Auto Loader through `STREAM read_files(...)`.
- Several streaming sources feeding one table MUST use one append flow per source
  (`CREATE FLOW ... AS INSERT INTO ... BY NAME`). `UNION` across streaming sources MUST NOT
  be used.
- Change feeds MUST be applied with `AUTO CDC INTO`, with explicit `KEYS`, `SEQUENCE BY`,
  and a delete condition placed before `SEQUENCE BY`. The plan MUST state whether the
  target is SCD type 1 or type 2. Queries for the current version of a type 2 table MUST
  filter `__END_AT IS NULL`.
- New datasets MUST NOT use `PARTITIONED BY`. Where physical layout matters, use
  `CLUSTER BY`.
- Each file MUST define one target dataset together with its flows, and MUST be named
  after that dataset.

**Rationale**: the wrong pairing either fails validation or yields results that are
quietly incorrect, such as an aggregate in a streaming table that never recomputes when its
source changes.

## Platform and Technology Constraints

- **Platform**: Databricks with Unity Catalog and serverless Lakeflow Spark Declarative
  Pipelines. The project MUST remain runnable on Databricks Free Edition; streaming is
  simulated with `availableNow` triggers in the data generators.
- **Catalog and schemas**: one catalog, `workspace`, with schemas `bronze`, `silver`, and
  `gold`. Persisted datasets MUST be referenced by three-level name. A reference to any
  other catalog is a violation.
- **Landing zone**: source files arrive in the volume `workspace.bronze.landing`, one
  folder per source. Pipeline code MUST NOT write to the landing volume.
- **Repository layout**: pipeline SQL lives in `code_tips/` under `01_bronze/`,
  `02_silver/`, and `03_gold/`. Generators and exploration notebooks live in
  `explorations/`. Documentation lives in `doc/`.
- **Naming**: object and column names are in Portuguese, lowercase snake_case. Silver
  tables use the prefix `tb_`, temporary views `vw_`, private staging tables `temp_tb_`,
  dimensions `dim_`, facts `fato_`, and one-big-tables `obt_`. Flows are named
  `<layer>_<target>[_<source>]_flow`.
- **Lineage columns**: conformed silver tables MUST carry `origem` (the source channel)
  and `data_carga` (the load timestamp).
- **Data**: all data is synthetic. Real personal data MUST NOT be loaded into this project.
- **CLI**: Databricks CLI commands MUST pass an explicit `--profile`. A profile MUST NOT be
  selected on the user's behalf.

## Development Workflow and Quality Gates

- Before writing or changing pipeline code, the `databricks-pipelines` skill and the
  reference file for each feature in use MUST be consulted. When the skill and this
  constitution disagree, the constitution prevails and the disagreement is raised as an
  amendment.
- Every feature plan MUST include a Constitution Check covering all five principles.
  Each deviation MUST be recorded with its justification and the simpler alternative that
  was rejected.
- A change is complete only when all of these hold:
  1. The pipeline validates and an update finishes without failed flows.
  2. The data quality tab shows every declared expectation with its metrics.
  3. Bronze, conformed, and quarantined row counts reconcile for each changed source.
  4. `doc/pipeline-reference.md` and `doc/architecture.md` describe the changed datasets,
     and `doc/known-issues.md` gains or loses entries as defects are found or fixed.
- A full refresh destroys streaming state and reprocesses sources from the beginning. It
  MUST be explicitly approved by the user and MUST NOT be run as a routine fix.
- Changing a dataset between streaming table and materialized view requires dropping the
  existing table. That drop MUST be explicitly approved by the user.
- Existing code that predates this constitution is brought into compliance when the file is
  next modified. Known gaps are tracked in `doc/known-issues.md`.

## Governance

This constitution takes precedence over other practices, conventions, and skill guidance in
this repository.

- **Amendments**: proposed by editing `.specify/memory/constitution.md` through
  `/speckit-constitution`, with the rationale stated. An amendment takes effect when the
  repository owner approves and commits it. An amendment that makes existing code
  non-compliant MUST list the affected files and how they will be migrated.
- **Versioning**: semantic versioning. MAJOR for removing or redefining a principle in a
  backward-incompatible way, MINOR for adding a principle or section or materially
  expanding guidance, PATCH for clarifications and wording.
- **Compliance review**: every plan, task list, and code review MUST verify compliance with
  the Core Principles. A violation is either fixed or justified in the plan's Complexity
  Tracking section; an unjustified violation blocks the change.
- **Runtime guidance**: `doc/` describes the project as built, and the
  `databricks-pipelines` skill gives syntax and patterns. Both inform implementation;
  neither overrides this document.

**Version**: 1.0.0 | **Ratified**: 2026-10-10 | **Last Amended**: 2026-10-10
