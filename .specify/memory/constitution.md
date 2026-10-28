<!--
SYNC IMPACT REPORT (scratch material for review; remove before committing)

Version change: 1.10.0 → 1.11.0
Bump rationale: MINOR. Principle I gains a bounded exception: the course feed's boundary
view is named `vw_bronze_tb_curso` and may convert the price and add `origem` and
`data_carga`. The `dim_curso` exception and the naming rule point to it. Nothing is
removed.
Owner, 2026-10-28 (feature 008, clarification): chose the diagram's name,
`vw_bronze_tb_curso`, "with a constitution amendment to allow it". The extra columns
follow from feature 008's plan: an `AUTO CDC` flow reads only a named view, so it cannot
compute columns.

Modified principles (titles unchanged):
- I. Medallion Architecture: new bullet "Exception: the course feed's boundary view".
  The `dim_curso` exception now reads `vw_bronze_tb_curso` instead of
  `vw_bronze_dados_database`.

Modified sections:
- Platform and Technology Constraints, Naming: boundary views follow
  `vw_<source zone>_<dataset>`, except `vw_bronze_tb_curso`.

Added sections: none
Removed sections: none

Dependent templates: not modified by this command; they read the constitution at runtime.

Affected files: none. No file defines a view over `bronze.dados_database` yet. Feature 008
(`specs/008-silver-tb-curso/plan.md`) recorded the two deviations in Complexity Tracking;
under v1.11.0 they are no longer deviations.

Follow-up TODOs:
- Feature 008 plan: re-check Principle I and Constraints against v1.11.0 (both PASS) and
  empty Complexity Tracking.
- Commit the v1.10.0 and v1.11.0 amendments (remove this report first).
- No deferred placeholders.
-->

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
  denormalized tables. Gold MUST read from silver or from other gold datasets, apart from
  the exception below.
- A dataset MUST NOT read from a later layer, and a layer MUST NOT be skipped, apart from
  the exception below.
- **Boundary views.** Before each zone change, the next zone MUST read the earlier zone
  through a temporary view that excludes the bronze lineage columns `source_file_name` and
  `_rescued_data`. Those columns belong to bronze only: silver and gold tables MUST NOT
  carry them. The view is named `vw_<source zone>_<dataset>` (for example
  `vw_bronze_dados_api`), lives in its own file in the reading zone's folder, and does
  nothing else: no filters, casts, renames or rules. Because only bronze carries those
  columns, every read of a bronze table goes through such a view. `processing_time` is not
  excluded by this rule.
- **Exception: the course feed's boundary view.** The boundary view over
  `bronze.dados_database` is named `vw_bronze_tb_curso`, the name drawn in
  `doc/lakeflow_architecture.png`. Besides excluding `source_file_name` and
  `_rescued_data`, it MAY convert `valor_curso` to `DECIMAL(9,2)` and add `origem` and
  `data_carga`, because the `AUTO CDC` flows that read it cannot compute columns. The
  exception is bounded as follows:
  - It applies only to this view. Any other boundary view that does more than exclude the
    lineage columns requires an amendment naming it here.
  - The view MUST NOT filter rows, rename columns, or change any other column.
  - `silver.tb_curso` and `gold.dim_curso` both read the feed through this view, so their
    current versions carry the same price type and record source.
- **Exception: SCD type 2 dimensions read the bronze change feed.** `gold.dim_curso` reads
  `bronze.dados_database` through its boundary view, `vw_bronze_tb_curso` (see the
  exception above), instead of reading silver. Its silver counterpart, `silver.tb_curso`, is an SCD
  type 1 target: it keeps only the latest version of each course and is updated and
  deleted in place, so it holds neither the history nor the ordered change events that
  `AUTO CDC ... STORED AS SCD TYPE 2` needs. The exception is bounded as follows:
  - It applies only to `gold.dim_curso`. Any other gold dataset that reads bronze requires
    an amendment naming it here.
  - The gold flow MUST use the same `KEYS`, `SEQUENCE BY`, and delete condition as the
    silver flow for the same source, so that the current gold version always equals the
    silver row.
  - The gold flow MUST NOT apply cleansing or business rules to the bronze feed beyond
    excluding lineage and change-control columns. If the feed needs validation, the rules
    of Principles III and IV apply to it before it reaches gold.
  - The bronze dependency MUST be stated in `doc/pipeline-reference.md`.
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
  - **`ON VIOLATION DROP ROW`**: remove rows, either routed to quarantine by the same
    predicate or dropped as a declared exclusion, both under Principle IV.
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
  validation table that reads the source's boundary view (Principle I) and adds a Boolean
  flag column (`fl_registro_invalido`) computed from the rejection rules.
- The same rules MUST also be declared on that validation table as warn expectations, so
  that every rejection is counted. The flag and the expectations MUST encode the same
  predicates; changing one without the other is a violation.
- Flagged rows MUST be written to a quarantine streaming table in silver
  (`tb_quarentena`, or `tb_quarentena_<source>` when sources differ in shape). Conformed
  silver tables MUST read only rows where the flag is false.
- A quarantine row MUST preserve the record as delivered by the boundary view: every
  source column, unchanged, without the lineage columns the view excludes. It MUST record
  which rule or rules rejected it.
- A quarantine table MUST carry every column of its validation table, with nothing
  excluded or replaced: the delivered record, the names of the failed rules, the flag,
  `origem` and the validation table's `data_carga`. It adds its own load time as
  `data_carga_quarentena`. All the evidence of a data issue is then in one row, without a
  join back to the private validation table.
- `ON VIOLATION DROP ROW` is permitted in two cases:
  - **Routed**: the dropped rows are also routed to a quarantine table by the same
    predicate.
  - **Declared exclusion**: on a conformed silver table's own rule, when the feature's
    plan names the rule and states why its rows need not be kept. The rule's failed count
    is the record of what was dropped. The rule MUST be listed as a reconciliation
    exclusion in `doc/pipeline-reference.md`. Rejection rules of a validation table never
    use this case: they always route to quarantine.

  Any other drop of a row that exists nowhere but bronze is a violation.
- For each source, rows in bronze MUST equal rows conformed plus rows quarantined, apart
  from exclusions documented in `doc/pipeline-reference.md`.

**Rationale**: dropping bad data hides upstream defects and makes totals impossible to
reconcile. Quarantine keeps the conformed flow clean while preserving the evidence and the
option to reprocess once the cause is fixed.

### V. Dataset Types and Flows That Fit the Source

The dataset type follows from the nature of the source, not from habit.

- **Bronze and silver are streaming.** Every dataset in bronze and silver MUST be declared
  as streaming: a **streaming table** (`CREATE OR REFRESH [PRIVATE] STREAMING TABLE`) or a
  **temporary view** whose query reads `STREAM(...)` or `STREAM read_files(...)`.
  Materialized views MUST NOT be used in bronze or silver. Whether a dataset runs as a
  stream or as a batch is decided by the pipeline's execution mode (triggered or
  continuous), not by the dataset type.
- Silver logic that combines data MUST be expressed in streaming form: append flows for
  several sources, `AUTO CDC INTO` for change feeds, and stream-static joins against
  reference data. A result that must be recomputed in full on every update (aggregations,
  joins across growing tables) belongs in gold.
- **Gold** is the exception. A full-scan result (joins across tables, aggregations, facts
  and denormalized tables) MUST be a **materialized view** read without `STREAM`. A gold
  dataset fed by a change feed, such as an `AUTO CDC ... STORED AS SCD TYPE 2` dimension,
  is a streaming table.
- Intermediate logic MUST default to a **temporary view**. A private streaming table (in
  bronze or silver) or a private materialized view (in gold only) is allowed only when
  materializing once avoids significant reprocessing, as with the validation table in
  Principle IV.
- File ingestion MUST use Auto Loader through `STREAM read_files(...)`.
- Several streaming sources feeding one table MUST use one append flow per source
  (`CREATE FLOW ... AS INSERT INTO ... BY NAME`). `UNION` across streaming sources MUST NOT
  be used.
- **Flow views.** Every append flow MUST read a temporary view that holds its whole query:
  source, filters, renames, casts and keys. The flow itself is only
  `INSERT INTO <target> BY NAME SELECT * FROM STREAM(<view>)`. The view is named
  `vw_<zone>_<target>_<source>` (for example `vw_silver_tb_venda_api`), lives in its own
  file numbered just before the target's file, and produces exactly the target's
  columns.
- Change feeds MUST be applied with `AUTO CDC INTO`, with explicit `KEYS`, `SEQUENCE BY`,
  and a delete condition placed before `SEQUENCE BY`. The plan MUST state whether the
  target is SCD type 1 or type 2. Queries for the current version of a type 2 table MUST
  filter `__END_AT IS NULL`.
- New datasets MUST NOT use `PARTITIONED BY`. Where physical layout matters, use
  `CLUSTER BY`.
- Each file MUST define one target dataset together with its flows, and MUST be named
  `NN_<dataset>.sql`: a two-digit prefix, sequential from `01` within its zone folder in
  reading order, followed by the dataset's name. The prefix orders reading only; execution
  order still comes from dependencies (Principle II).

**Rationale**: declaring bronze and silver as streaming gives every dataset incremental
state, so each row is processed once and the pipeline's execution mode alone decides
latency and cost. Keeping full recomputation in gold confines the one case where streaming
is wrong: an aggregate in a streaming table that never recomputes when its source
changes.

### VI. Record Source and Hash Keys in Silver

Silver adopts two Data Vault practices: every row states where it came from, and every row
is identified by a deterministic hash key. Silver is not otherwise modeled as a Data Vault;
hubs, links, and satellites are out of scope.

- **Record source.** Every silver table, quarantine tables included, MUST carry `origem`,
  naming the source system that delivered the row (`API`, `ARQUIVO`, `DATABASE`). The value
  MUST be a literal set by the flow that reads that source. It MUST NOT be derived from the
  data, defaulted, or null.
- **Load timestamp.** Every silver table MUST carry `data_carga`, the time the row was
  loaded.
- **Hash key.** Every conformed silver table MUST carry a hash key that identifies the row,
  named `<entidade>_uuid` (for example `usuario_uuid`, `curso_uuid`, `venda_uuid`).
  - The hash key MUST be computed with `md5` over the business key columns only. It MUST
    NOT include load timestamps, random values, or any other non-deterministic input, so
    that reprocessing the same source row yields the same key.
  - A key built from several columns MUST cast each component to `STRING`, replace `NULL`
    with a fixed placeholder, and join the components with a delimiter, as in
    `md5(concat_ws('||', coalesce(cast(a AS STRING), ''), coalesce(cast(b AS STRING), '')))`.
    Bare `concat` MUST NOT be used: it returns `NULL` when any component is null and lets
    different keys collide.
  - The record source is part of the business key whenever two sources can issue the same
    identifier for different things.
- **One expression per key.** Every dataset that computes a given hash key MUST use the
  same expression, written identically, over the same business key columns. A key
  computed with a different expression in another file is a violation. Each feature that
  computes a key already computed elsewhere MUST verify that the two join, for example
  that every user key in an access table exists in the user table. No shared view is
  required to hold the expression.
- **Uniqueness.** A hash key MUST be unique within its table. Each conformed silver table
  MUST declare an expectation that its hash key is not null, and uniqueness
  (`count(*) = count(DISTINCT <entidade>_uuid)`) MUST be verified before a change is
  accepted. A table that legitimately receives the same business key more than once MUST
  either deduplicate on the hash key or apply `AUTO CDC` keyed on it.
- **References.** A silver table refers to another entity by that entity's hash key, under
  the same column name.
- The business key columns behind each hash key MUST be listed in
  `doc/pipeline-reference.md`.
- **Exception: `silver.tb_curso` does not derive a hash key.** The course catalog has a
  single source, the database change feed, and that feed already delivers the course
  identifier. No key needs to be unified across sources, so the hash key rules above
  (derivation with `md5`, the composition rule, the not-null expectation, and the
  uniqueness check) do not apply to this table. The exception is bounded as follows:
  - It applies only to `silver.tb_curso`. It ends if a second source of courses is added.
  - The table keeps the identifier delivered by the source, unchanged, as the `KEYS`
    column of its `AUTO CDC` flow, which is what keeps one row per course.
  - The record source and load timestamp rules still apply: `tb_curso` MUST carry `origem`
    and `data_carga`.
  - Other silver tables that reference a course MUST produce a value equal to the
    identifier delivered by the source, so that they join to `tb_curso` and to
    `gold.dim_curso`.

**Rationale**: the record source makes every row traceable to its origin after sources are
merged. A deterministic hash key gives sources with different native identifiers one
uniform key, makes reloads idempotent, and gives gold a stable business key to join on.
Two expressions for the same key produce joins that fail without any error.

### VII. Kimball Dimensional Modeling in Gold

Gold is a dimensional model built by Kimball's rules.

- **Star schema.** Gold consists of fact tables (`fato_`) and dimension tables (`dim_`).
  Dimensions MUST be denormalized; a dimension MUST NOT reference another dimension.
- **Declared grain.** Every fact table MUST state its grain, meaning what one row
  represents, in `doc/pipeline-reference.md` before it is built. Every row MUST be at that
  grain, and every measure MUST be valid at that grain.
- **Facts hold keys and measures.** A fact table contains surrogate keys to its dimensions,
  numeric measures, and degenerate dimensions (identifiers with no attributes, such as a
  transaction number). Descriptive attributes belong in dimensions. Each measure MUST be
  documented as additive, semi-additive, or non-additive.
- **Surrogate keys.** Every dimension MUST have a single-column surrogate key named
  `sk_<dimensao>`. Facts MUST reference dimensions only through surrogate keys. The
  surrogate key of a given dimension row MUST keep its value across pipeline updates; a
  mechanism that reassigns keys on refresh MUST NOT be used.
- **Business keys.** Every dimension MUST retain the silver hash key (Principle VI) as its
  business key; for `dim_curso` this is the identifier delivered by the source. Surrogate
  keys are resolved by joining on that key.
- **Conformed dimensions.** A dimension shared by several facts is defined once and reused
  unchanged. Two dimensions describing the same entity MUST NOT coexist.
- **Date dimension.** Facts MUST reference the calendar dimension (`dim_tempo`) through its
  surrogate key instead of storing date attributes.
- **Slowly changing dimensions.** Every dimension MUST declare its type. Type 1 overwrites
  in place. Type 2 keeps history through `AUTO CDC ... STORED AS SCD TYPE 2`, with one
  surrogate key per version. A fact that references a type 2 dimension resolves the
  version in effect when the fact event happened; resolving the current version
  (`__END_AT IS NULL`) instead is allowed only when the plan states it and explains why.
- **No null foreign keys.** Every dimension key in a fact MUST be populated. Each dimension
  MUST provide explicit members for "unknown" and "not applicable", and facts point to
  them when a lookup has no match. This is what makes the reconciliation rule of
  Principle I achievable.
- **Junk dimensions.** Low-cardinality flags and codes that belong to no other dimension
  are grouped into a junk dimension (`dim_codigos`) instead of being stored on the fact or
  given one dimension each.
- **Derived tables.** A one-big-table (`obt_`) is a denormalized convenience for one
  analysis. It MUST state its grain, and it MUST NOT be the only place a business measure
  is defined.

**Rationale**: a declared grain and conformed dimensions keep measures consistent across
every query and every fact. Surrogate keys isolate the model from source key changes and
make type 2 history possible. Default members keep row counts honest by replacing silent
loss with an explicit "unknown".

## Platform and Technology Constraints

- **Platform**: Databricks with Unity Catalog and serverless Lakeflow Spark Declarative
  Pipelines. The project MUST remain runnable on Databricks Free Edition; streaming is
  simulated with `availableNow` triggers in the data generators.
- **Catalog and schemas**: one catalog, `workspace`, with schemas `bronze`, `silver`, and
  `gold`. Persisted datasets MUST be referenced by three-level name. A reference to any
  other catalog is a violation.
- **Landing zone**: source files arrive in the volume `workspace.bronze.landing`, one
  folder per source. Pipeline code MUST NOT write to the landing volume.
- **Repository layout**: code is split by purpose into two top-level folders. Code MUST
  NOT be created at the repository root or in any other top-level folder.
  - `src/` holds the project's own code, meaning what is deployed and run as the product:
    the pipeline SQL, in `src/pipeline/` under `01_bronze/`, `02_silver/`, and `03_gold/`.
    Every script in a zone folder carries the `NN_` prefix of Principle V, numbered from
    `01` in each folder.
    The pipeline's source path points to `src/pipeline/` and nowhere else. A new kind of
    project code gets a new subfolder of `src/`, named in the feature's plan.
  - `explorations/` holds all auxiliary code, meaning anything that supports the project
    without being part of the deployed pipeline: exploration notebooks, data generators,
    clean-up notebooks, and the initial environment setup. Setup scripts live in
    `explorations/setup/`, numbered with the same `NN_` prefix in the order they run.
  - Auxiliary code MUST NOT be placed under `src/`, and project code MUST NOT be placed
    under `explorations/`. When it is unclear which kind a file is, the test is whether
    the pipeline needs the file to be deployed in order to run: if not, it is auxiliary.
  - Outside both folders: documentation lives in `doc/`, specifications in `specs/`, and
    configuration files that a tool requires at the repository root (`databricks.yml`,
    `pyproject.toml`, `uv.lock`, `.gitignore`) stay at the root. These are not code for the
    purposes of this rule.
- **Naming**: object and column names are in Portuguese, lowercase snake_case. Silver
  tables use the prefix `tb_`, temporary views `vw_` (boundary views
  `vw_<source zone>_<dataset>`, except `vw_bronze_tb_curso`, Principle I), private
  staging tables `temp_tb_`, dimensions `dim_`, facts `fato_`, and one-big-tables `obt_`.
  Flows are named `<layer>_<target>[_<source>]_flow`.
- **Key and lineage columns**: hash keys end in `_uuid`, surrogate keys start with `sk_`,
  the record source is `origem`, and the load timestamp is `data_carga`, as defined in
  Principles VI and VII.
- **Data**: all data is synthetic. Real personal data MUST NOT be loaded into this project.
- **CLI**: Databricks CLI commands MUST pass an explicit `--profile`. A profile MUST NOT be
  selected on the user's behalf.
- **AI tools**: Databricks AI tools are part of the development toolkit, within the limits
  below. Every one of them is optional: the pipeline MUST validate, run and reconcile
  without any of them, so the project stays runnable on Databricks Free Edition and in a
  workspace where a tool is disabled. All data is synthetic, so nothing in this project is
  withheld from these tools.
  - **Databricks Assistant** MAY be used to write, explain and debug pipeline SQL, and to
    diagnose a failed update. Its output is a draft: a person reviews it against this
    constitution before it is committed. Generated code that uses legacy syntax
    (Principle II), a bare `WHERE` in place of an expectation (Principle III), or a hash
    key expression different from the one already in use (Principle VI) MUST be rewritten
    before use.
  - **Genie** MAY be used to explore data and to answer questions during development,
    reconciliation and demonstrations. It is read-only: it MUST NOT create, alter or write
    datasets. A Genie Agent built for this project MUST be defined over `workspace.gold`
    only; bronze and silver are not exposed to it. When a Genie answer is used as evidence
    for a quality gate, the SQL that Genie generated is the evidence, not the question.
  - **AI Functions** (`ai_query`, `ai_classify`, `ai_extract` and the rest of the `ai_*`
    family) MUST NOT be used in bronze, silver or gold datasets. A model call is not
    deterministic: a reload could produce different rows, a hash key over its result would
    drift (Principle VI), and bronze-to-silver reconciliation could no longer be explained
    (Principles I and IV). Principle III already excludes them from expectation
    conditions. They MAY be used under `explorations/`, for synthetic data generation and
    exploration. A pipeline use that needs one MUST be raised as an amendment naming the
    dataset and the function.
  - **Agent Bricks** (Knowledge Assistant, Supervisor Agent, Information Extraction and
    the other Agent Bricks types) are consumers of gold, like a dashboard. They MUST NOT
    feed any dataset, and the pipeline MUST NOT depend on one. An agent built for this
    project reads `workspace.gold` only and is named in `doc/architecture.md` as a
    consumer.

## Development Workflow and Quality Gates

- Before specifying or planning a feature, the target dataset graph in
  `doc/lakeflow_architecture.png`, together with `doc/architecture.md`, MUST be consulted.
  A feature MUST NOT add datasets the graph does not show, and every difference from the
  graph MUST be justified in the plan's Constitution Check. The one exception is a flow
  view required by Principle V: it is allowed where the graph does not draw it, and the
  plan lists it.
- Before writing or changing pipeline code, the `databricks-pipelines` skill and the
  reference file for each feature in use MUST be consulted. When the skill and this
  constitution disagree, the constitution prevails and the disagreement is raised as an
  amendment.
- Code and answers produced by Databricks Assistant, Genie, or any other AI tool are
  drafts. They are held to the Core Principles like any other change, reviewed by a person
  before they are committed, and never substitute for the approvals this section
  requires: a full refresh and a table drop remain decisions of the user.
- Every feature plan MUST include a Constitution Check covering every Core Principle.
  Each deviation MUST be recorded with its justification and the simpler alternative that
  was rejected.
- A change is complete only when all of these hold:
  1. The pipeline validates and an update finishes without failed flows.
  2. The data quality tab shows every declared expectation with its metrics.
  3. Bronze, conformed, and quarantined row counts reconcile for each changed source.
  4. Every changed silver table has a populated `origem` and, unless exempted by
     Principle VI, a unique, non-null hash key.
  5. Every changed fact has a documented grain, no null dimension keys, and a row count
     that reconciles with its silver source.
  6. `doc/pipeline-reference.md` and `doc/architecture.md` describe the changed datasets,
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

**Version**: 1.11.0 | **Ratified**: 2026-10-10 | **Last Amended**: 2026-10-28
