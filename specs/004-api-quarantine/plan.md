# Implementation Plan: Validation and Quarantine of API Events

**Branch**: `004-api-quarantine` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-api-quarantine/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Classify every bronze API event once, at the bronze-to-silver boundary. Events that fail
a rule are kept, unchanged, in a quarantine table. The others stay available for the
conformed silver tables of later features.

Technical approach, from [research.md](research.md): two SQL files under
`src/pipeline/02_silver/`.

- `temp_tb_validacao_api.sql`: a private streaming table, clustered on the flag. It reads
  `STREAM(workspace.bronze.dados_api)` and keeps every column. It declares the four rules
  as warn-only expectations: the three from the request, null-safe, plus the
  rescued-data rule the constitution requires. It adds `regras_violadas` (the names of
  the failed rules), the flag `fl_registro_invalido` derived from it, `origem = 'API'` and
  `data_carga`.
- `tb_quarentena.sql`: a published streaming table holding the flagged rows, with a
  warn expectation that each one names a rule.

Validation compares the quarantine table and the event log metrics with counts computed
directly on bronze.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE OR REFRESH [PRIVATE] STREAMING TABLE`, `STREAM(...)`, `CONSTRAINT ... EXPECT`,
`CLUSTER BY`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless); Unity
Catalog; Databricks CLI v1.11.0; the pipeline event log (`event_log(...)`) for metrics

**Storage**: reads the streaming table `workspace.bronze.dados_api`. Writes one private
streaming table and one managed streaming table in `workspace.silver`

**Testing**: pipeline dry run (`--validate-only`), then the queries of
[quickstart.md](quickstart.md). They compare quarantine contents and expectation metrics
with counts computed directly on bronze. No test framework

**Target Platform**: Databricks Free Edition workspace, the existing development pipeline
`lakeflow_dataslight_dev`

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: the first update validates every bronze API event in one triggered
run. An update with no new bronze rows writes 0 rows to both tables

**Constraints**: validation removes nothing; rules only measure; no `PARTITIONED BY`; no
full refresh without the owner's approval; CLI profile always passed explicitly

**Scale/Scope**: 2 SQL files, 2 tables, 5 expectations, 3 documentation updates. The
pipeline settings are unchanged, because the source glob already covers `02_silver/`

Nothing is marked NEEDS CLARIFICATION. Two facts are confirmed at implementation, with a
defined response if they come out differently ([research.md](research.md), Decisions 2
and 4):

- that the dry run accepts a three-level name and `CLUSTER BY` on a private table;
- the inferred type of `payload.info_pagamento.valor`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.5.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Both tables are in `workspace.silver` and read only bronze or silver, moving forward. Each carries `TBLPROPERTIES ("quality" = "silver")`. Every dataset read is defined in the pipeline. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Two `.sql` files, declarative, in current syntax. No `LIVE`, no `APPLY CHANGES`, no `CREATE OR REPLACE`, no imperative statements. |
| III. Data Quality Through Expectations | Yes | PASS | The four rules are named `CONSTRAINT ... EXPECT` clauses on the validation table. The quarantine table declares `regra_violada_registrada`. Every action is warn, deliberately: rows must survive to be routed (Principle IV). Every condition states its `NULL` treatment (`IS NULL OR ...`) and cannot return `NULL`. Names are unique per dataset. No subqueries or UDFs. The quarantine `WHERE` is a routing filter, not the only expression of a rule: the rules are measured upstream. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | One validation, at the boundary, in a private table with `fl_registro_invalido`. The rules are written both as warn expectations and as the source of the flag, with the same predicates (research, Decision 5). Flagged rows go to `workspace.silver.tb_quarentena`, unchanged, with `regras_violadas`. Rows with `_rescued_data` are quarantined (`registro_nao_conforme`). No `DROP ROW`. Bronze = valid + quarantined is checked in the quickstart. Conformed tables reading only the false side is fixed in the contract for later features. |
| V. Dataset Types and Flows | Yes | PASS | Incremental source, so streaming tables over `STREAM(...)`. The private streaming table is justified: it is the materialized split point read by quarantine and by every later conformed table (research, Decision 2). `CLUSTER BY`, no `PARTITIONED BY`. One dataset per file, named after it. Single source, so no `CREATE FLOW`. |
| VI. Record Source and Hash Keys | Yes | PASS | `origem = 'API'` (literal) and `data_carga` on both tables. Hash keys are required on conformed silver tables. Neither table here is conformed: one is staging, one holds rejected records unchanged. So no hash key is derived (research, Decision 6). |
| VII. Kimball Dimensional Modeling | No | N/A | No gold dataset. |
| Constraints: platform | Yes | PASS | Serverless, triggered updates, Free Edition. |
| Constraints: catalog and schemas | Yes | PASS | Every name is three-level in `workspace`. The private table keeps its three-level name; if the dry run refuses it, the work stops for the owner instead of falling back to the default schema. |
| Constraints: landing zone | Yes | PASS | Not read or written by this feature. |
| Constraints: repository layout | Yes | PASS | Project code in `src/pipeline/02_silver/`, the folder the constitution names. No auxiliary code. |
| Constraints: naming | Yes | PASS | `temp_tb_` for the private staging table and `tb_` for the silver table. Columns are in Portuguese snake_case (`regras_violadas`, `fl_registro_invalido`, `origem`, `data_carga`); bronze columns keep their names. No explicit flows, so no flow names. |
| Constraints: data, CLI | Yes | PASS | Synthetic data; every command takes `--profile`. |
| Workflow: consult `databricks-pipelines` skill | Yes | PASS | Consulted: `SKILL.md`, `streaming-table-sql.md`, `expectations-sql.md`. The skill and the constitution agree on everything this feature uses. |
| Workflow: completion gates | Yes | PLANNED | Gate 1 (validates, update finishes) and gate 2 (data quality tab shows the 5 expectations) are quickstart steps 2 and 4. Gate 3 is quickstart steps 3–4, with the conformed side measured as the validation table's false rows. Gate 4: `origem` populated, and hash keys not applicable (Principle VI). Gate 5: no fact. Gate 6: documentation tasks below. |
| Workflow: full refresh / type change | Yes | PASS | Both tables are new, so a normal update fills them. No full refresh and no drop. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations. The owner's request to partition by the
flag was resolved as clustering before planning, so it needs no Complexity Tracking entry.
The contract turns Principles III and IV into a list of what each statement must and must
not contain, including a rule against writing a predicate differently in its two places.

## Project Structure

### Documentation (this feature)

```text
specs/004-api-quarantine/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── silver-validation-quarantine.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    ├── 01_bronze/                        # unchanged (feature 003)
    │   ├── dados_api.sql
    │   ├── dados_files.sql
    │   └── dados_database.sql
    └── 02_silver/                        # NEW folder
        ├── temp_tb_validacao_api.sql     # NEW: private validation table, 4 rules, flag
        └── tb_quarentena.sql             # NEW: quarantine of flagged API events

doc/
├── pipeline-reference.md                 # CHANGED: silver sections for both tables replace the earlier pipeline's
├── architecture.md                       # CHANGED: graph and feature table point to src/pipeline/02_silver/
└── known-issues.md                       # CHANGED: the old quarantine's catalog-name entry is resolved
```

**Structure Decision**: the two definitions are project code and open the `02_silver/`
layer folder that the constitution names. File names carry no numeric prefix, as in
`01_bronze/`: execution order comes from dependencies, and each file is named after its
dataset. The pipeline's glob picks the folder up, so `explorations/setup/03_pipeline_dev.json`
does not change.

## Design Notes for Implementation

These carry the decisions of [research.md](research.md) into the task phase.

- **Consult the skill first.** Read `databricks-pipelines` (`streaming-table-sql.md`,
  `expectations-sql.md`) before writing the files, as the constitution requires.
- **Two parallel lists in the validation file.** Write the four `CONSTRAINT` clauses and
  the four `CASE WHEN NOT (...)` lines in the same order and with identical conditions.
  Lay them out so that a reviewer can compare them line by line. The conditions are
  exactly those of [data-model.md](data-model.md#validation-rules).
- **Select list order.** `*` first, then `regras_violadas`, `fl_registro_invalido`,
  `origem`, `data_carga`. The quarantine file uses `* EXCEPT (fl_registro_invalido,
  data_carga)` followed by a new `data_carga`.
- **Comments in Portuguese**, one short header comment per file and the table `COMMENT`,
  matching the bronze files.
- **Check the payment value's type first** (quickstart step 1). If the rule would reject
  nothing, report it before writing code.
- **Dry run before the real run.** If it rejects the qualified private name, `CLUSTER BY`
  on a private table, or the lateral alias, apply only the fallback the research and the
  contract allow (a subquery for the alias). Report the other two to the owner.
- **Documentation replaces, not appends.** `doc/pipeline-reference.md` currently describes
  the earlier pipeline's `temp_tb_validacao_api` ("partitioned by `fl_registro_invalido`",
  three rules, reading `vw_bronze_dados_api`) and `tb_quarentena`. Rewrite both sections
  for the new design, including the rescued-data rule, `regras_violadas` and the
  consumer rule for conformed tables. In `doc/architecture.md`, drop `vw_bronze_dados_api`
  from the API path of the graph and point the quarantine rows of the feature table to the
  new files. In `doc/known-issues.md`, remove the `04_tb_quarentena.sql` row of the catalog
  mismatch and its paragraph, since the new quarantine reads `workspace`.

## Complexity Tracking

No violations to justify.
