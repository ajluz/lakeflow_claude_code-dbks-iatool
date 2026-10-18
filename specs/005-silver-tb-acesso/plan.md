# Implementation Plan: Silver Access Table from API Events

**Branch**: `005-silver-tb-acesso` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

## Revision 2026-10-18: constitution v1.8.0

The owner asked why so many views were being created, and whether
`doc/lakeflow_architecture.png` had been considered. It had not: the specs and plans of
features 005 and 006 were written without consulting the diagram. The owner chose to
match the diagram:
- **Graph**: `tb_acesso` reads `workspace.silver.temp_tb_validacao_api` directly, with
  `WHERE NOT fl_registro_invalido`, as the diagram's edge `temp_tb_validacao_api →
  tb_acesso` shows. `vw_silver_eventos_api` (file `04_`) was removed.
- **Keys**: `timestamp_acesso`, `usuario_uuid` and `curso_uuid` are computed inline in
  `tb_acesso`. `usuario_uuid` uses the same expression as `tb_usuario`, written character
  for character the same. Constitution v1.8.0 replaced "one definition per key" with "one
  expression per key" and made the diagram the target graph.
- **Files**: `src/pipeline/02_silver/05_tb_acesso.sql` keeps its name; feature 004's files
  were renumbered (`03_temp_tb_validacao_api.sql`, `04_tb_quarentena.sql`).
- **Data**: the keys keep the same values, so the rows after the refresh are the same.
  `tb_acesso` needs a refresh, which needs the owner's approval.

The sections below record the first design and remain as history where they mention
`vw_silver_eventos_api`.

**Input**: Feature specification from `/specs/005-silver-tb-acesso/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Turn every valid API event into one conformed access row in `workspace.silver.tb_acesso`.
Each row has a typed access time, the address, a device category (`Mobile`, `Computador`,
`unknown`), a deterministic access key, and the keys of the user and course it refers to.
The table demonstrates the three expectation actions:
- **drop**: the impossible address `999.999.999.999`, as a declared exclusion, not
  quarantined;
- **count only**: an unknown device;
- **stop the run**: the same unknown-device rule, present but commented out.

Technical approach, from [research.md](research.md): two SQL files under
`src/pipeline/02_silver/`.

- `04_vw_silver_eventos_api.sql`: a streaming temporary view of the valid events of feature
  004 (`WHERE NOT fl_registro_invalido`). It defines `timestamp_acesso`, `usuario_uuid` and
  `curso_uuid` once, for every API-based silver table.
- `05_tb_acesso.sql`: a streaming table with the 8 requested columns and 4 expectations.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`, `STREAM(...)`,
`CONSTRAINT ... EXPECT ... [ON VIOLATION DROP ROW]`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless); Unity
Catalog; Databricks CLI v1.11.0; the pipeline event log for metrics

**Storage**: reads the private table `workspace.silver.temp_tb_validacao_api` (feature
004). Writes one managed streaming table, `workspace.silver.tb_acesso`

**Testing**: dry run, then the queries of [quickstart.md](quickstart.md), compared with
counts computed directly from bronze. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: the first update loads the 2.5 million valid events in one
triggered run. An update with no new events writes 0 rows

**Constraints**:
- deterministic `md5` keys;
- each reference key is defined once;
- no materialized view in silver;
- no refresh of existing tables;
- the Free Edition quota needs a stopped warehouse and about 4 minutes between updates.

**Scale/Scope**: 2 SQL files, 1 view, 1 table, 4 expectations (1 more commented),
3 documentation updates. 2,516,192 rows expected on 2026-10-18

Nothing is marked NEEDS CLARIFICATION. The data facts behind every decision were read on
2026-10-18 and are recorded in [research.md](research.md). Among them:
- `access_date` parses as ISO-8601;
- the six device values;
- 25,523 impossible addresses;
- unique keys among the kept rows;
- all three products join the catalog.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.7.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Silver reads silver (the validation table); no zone change, so no boundary view is needed. `source_file_name` and `_rescued_data` are absent, as they already are upstream. `TBLPROPERTIES ("quality" = "silver")`. Every dataset read is defined in the pipeline. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Two `.sql` files, declarative, current syntax. No legacy forms. |
| III. Data Quality Through Expectations | Yes | PASS | Four named expectations, each with a deliberate action: one `DROP ROW`, three warn. The `FAIL UPDATE` variant is commented out, so it is not active. Every condition states its `NULL` treatment. No subqueries or UDFs. The table declares more than the one expectation silver requires. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | `check_endereco_ip_acesso` uses the **declared exclusion** case of v1.7.0. The rule belongs to a conformed table, not a validation table. This plan names it and gives the reason: the owner wants each action shown once, and the address is a generator artifact (research, Decision 4). Its failed count records the 25,523 rows, and `doc/pipeline-reference.md` lists it as an exclusion. Rows that feature 004 rejects stay in quarantine; `tb_acesso` reads only the valid side. |
| V. Dataset Types and Flows | Yes | PASS | Silver is streaming: a temporary view over `STREAM(...)` and a streaming table over `STREAM(...)`. No materialized view. The view is intermediate logic shared by later tables. No layout clause. Files `04_` and `05_` continue the zone's numbering. Single source, so no `CREATE FLOW`. |
| VI. Record Source and Hash Keys | Yes | PASS | `origem = 'API'` (literal) and `data_carga`. `acesso_uuid` is `md5` over `timestamp_acesso`, `endereco_ip_acesso` and `local_acesso`, each cast and `coalesce`d and joined with `'\|\|'`; it has a not-null expectation and is unique among kept rows (verified). `usuario_uuid` and `curso_uuid` are defined once, in the shared view. `curso_uuid` equals the catalog identifier, as the `tb_curso` exception requires. The business key columns go into `doc/pipeline-reference.md`. |
| VII. Kimball Dimensional Modeling | No | N/A | No gold dataset. |
| Constraints: platform, catalog, landing | Yes | PASS | Serverless, Free Edition; three-level names in `workspace`, unqualified temporary view; the landing volume is not touched. |
| Constraints: repository layout and naming | Yes | PASS | `src/pipeline/02_silver/`, `NN_` prefixes. `tb_` table, `vw_` view. Columns are Portuguese snake_case; `_uuid` suffix for hash keys. |
| Constraints: data, CLI | Yes | PASS | Synthetic data; `--profile databricks-free` on every command. |
| Workflow: consult `databricks-pipelines` skill | Yes | PASS | `streaming-table-sql.md`, `expectations-sql.md`, `temporary-view-sql.md` read for feature 004 and re-checked; no disagreement. |
| Workflow: completion gates | Yes | PLANNED | Gate 1: dry run and update (quickstart step 2). Gate 2: the 4 expectations in the data quality tab (step 4). Gate 3: valid = `tb_acesso` + declared exclusion (step 4). Gate 4: `origem` populated, `acesso_uuid` unique and not null (step 3). Gate 5: no fact. Gate 6: documentation. |
| Workflow: full refresh / type change | Yes | PASS | New datasets only. No refresh. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations. The only potential conflict,
dropping rows without quarantine, was resolved by the owner's amendment to v1.7.0 before
planning. This plan meets that amendment's two conditions: it names the rule and gives the
reason, and it lists the exclusion in the docs.

## Project Structure

### Documentation (this feature)

```text
specs/005-silver-tb-acesso/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── silver-tb-acesso.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    ├── 01_bronze/                          # unchanged
    └── 02_silver/
        ├── 01_vw_bronze_dados_api.sql      # unchanged (feature 004)
        ├── 02_temp_tb_validacao_api.sql    # unchanged (feature 004)
        ├── 03_tb_quarentena.sql            # unchanged (feature 004)
        ├── 04_vw_silver_eventos_api.sql    # NEW: valid API events + timestamp_acesso, usuario_uuid, curso_uuid
        └── 05_tb_acesso.sql                # NEW: conformed access table, 4 expectations

doc/
├── pipeline-reference.md   # CHANGED: tb_acesso section as built; the view; key business columns; the declared exclusion
├── architecture.md         # CHANGED: graph (T1 → new view → S2) and feature table (DROP ROW, commented FAIL UPDATE)
└── README.md               # CHANGED: layout lists 04_ and 05_, dataset count
```

**Structure Decision**: the two definitions continue the `02_silver/` numbering in
reading order. The pipeline's glob already covers the folder, so its settings do not
change.

## Design Notes for Implementation

- **The view owns the reference keys.** `usuario_uuid` and `curso_uuid` are computed in
  `04_vw_silver_eventos_api.sql` only. `05_tb_acesso.sql` selects them by name. Later
  user and sales tables must do the same.
- **`acesso_uuid` uses the derived `local_acesso`.** Compute the `CASE` first, as a
  lateral alias, then the key from it. This way the key matches what the table shows.
- **The commented rule** goes on the line right after the active `check_local_acesso`.
  Both use the same name, and a header comment says how to switch them.
- **Header comments in Portuguese** state the three actions, and that the drop is a
  declared exclusion not routed to quarantine.
- **Upload with `import-dir`** adds the two files. Nothing needs deleting this time.
- **If the first real update fails** after creating `tb_acesso`, and its columns change
  before a successful run, ask the owner to refresh `tb_acesso` alone (feature 004's
  lesson).
- **Documentation**: in `doc/pipeline-reference.md`, rewrite `### tb_acesso` as built,
  cover the view in `### Temporary views`, and add the declared exclusion to the API
  reconciliation line. In `doc/architecture.md`, route the graph `T1 --> V(new) --> S2`
  and update the feature-table rows "Expectations with `ON VIOLATION DROP ROW`" and
  "commented `FAIL UPDATE`" to the new file. In `doc/README.md`, list `04_` and `05_` in
  the layout and update the dataset count.

## Complexity Tracking

No violations to justify.
