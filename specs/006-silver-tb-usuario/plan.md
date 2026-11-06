# Implementation Plan: Silver User Table from API Events and Partner Files

**Branch**: `006-silver-tb-usuario` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

## Revision 2026-11-06: the sex rule becomes informative

The owner asked that `check_sexo_usuario` stop removing users and only record the error
(tasks, Phase 9).
- **`08_tb_usuario.sql`**: the expectation stays with its predicate, and
  `ON VIOLATION DROP ROW` is commented out, so the change is visible in the code.
- **`06_` and `07_` flow views**: `sexo_usuario` is
  `CASE WHEN <sexo> IN ('M', 'F') THEN <sexo> END`, so a sex other than `M` or `F`
  becomes empty. The rule counts those rows as failures.
- **Principle IV**: the declared exclusion is gone. Candidates now equal rows, and
  `doc/pipeline-reference.md` no longer lists an exclusion for `tb_usuario`.
- **Data**: the dropped users came back only through a full refresh. The owner approved
  refreshing `silver.tb_usuario`, `gold.dim_usuario` (its stream source was rewritten) and
  `gold.fato_venda` (keys are resolved once), through `full_refresh_selection`.

The sections below describe the earlier drop rule and remain as history.

## Revision 2026-10-18: constitution v1.9.0

**Flow views (constitution v1.9.0, owner, 2026-10-18, about 16:57 UTC)**: the owner
asked that every append flow read a view that holds its whole query, so that the pipeline
is simpler to read. The constitution was amended to v1.9.0 (Principle V, "Flow views"),
with an exception to the target-graph rule for these views. The not-yet-run deploy of the
v1.8.0 restructure was stopped before its dry run. New layout:
- `06_vw_silver_tb_usuario_api.sql`: valid API events with a user, in the 10 columns;
  `usuario_uuid` uses the same expression as `tb_acesso`;
- `07_vw_silver_tb_usuario_files.sql`: `vw_bronze_dados_files` in the 10 columns;
- `08_tb_usuario.sql`: the target and two flows, `silver_tb_usuario_api_flow` and
  `silver_tb_usuario_files_flow` (renamed from `_arquivo_` to match the diagram's
  `_files`), each `SELECT * FROM STREAM(<view>)`.

These are the same two per-source views removed in the v1.8.0 restructure, now required
by the constitution and named by its convention.

## Revision 2026-10-18: constitution v1.8.0

The owner asked why so many views were being created, and whether
`doc/lakeflow_architecture.png` had been considered. It had not. The owner chose to
match the diagram:
- **Graph**: `tb_usuario` reads `workspace.silver.temp_tb_validacao_api` (valid events
  with a user) and `vw_bronze_dados_files` directly, as the diagram's edges show.
  `vw_silver_eventos_api`, `vw_silver_vendas_arquivo`, `vw_silver_usuario_api` and
  `vw_silver_usuario_arquivo` were removed. Each append flow shapes its columns inline.
- **Keys**: the API `usuario_uuid` is computed in the flow, with the same expression as
  `tb_acesso`. The files `usuario_uuid` is computed in its flow. Constitution v1.8.0
  replaced "one definition per key" with "one expression per key".
- **Files**: `02_vw_bronze_dados_files.sql` (was `06_`) and `06_tb_usuario.sql` (was
  `10_`), in the diagram's reading order.
- **Data**: the key values do not change, so the rows after the refresh are the same.
  `tb_usuario` needs a refresh, which needs the owner's approval.

The sections below record earlier designs (`AUTO CDC`, then shaping views) and remain as
history.

**Input**: Feature specification from `/specs/006-silver-tb-usuario/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Build `workspace.silver.tb_usuario` from two sources: users carried by valid API events,
and employees in the partner companies' sales files. Each row has a deterministic user
key, the person's attributes, the company for corporate users, and the record source.
Users whose sex is not `M` or `F` are dropped as a declared exclusion. Invalid emails are
only counted.

Technical approach, from [research.md](research.md): five SQL files under
`src/pipeline/02_silver/`.
- **`06`**: the boundary view of the files source.
- **`07`**: a shared files view that defines the files user key once.
- **`08`, `09`**: one shaping view per source.
- **`10`**: `tb_usuario`, a streaming table fed by two append flows (`INSERT INTO ...
  BY NAME`), one per source. Both keys are unique in the data, so no merge is needed;
  uniqueness is verified after each load.
- **Revision (owner, 2026-10-18)**: the first design used two `AUTO CDC` SCD type 1
  flows and was deployed once. The owner replaced them with append flows as simpler and
  sufficient, and approved a refresh of `tb_usuario` alone for the switch.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`,
`CREATE FLOW ... AS INSERT INTO ... BY NAME`, `CONSTRAINT ... EXPECT`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless), two append
flows on one target; Unity Catalog; Databricks CLI v1.11.0

**Storage**:
- reads `vw_silver_eventos_api` (feature 005);
- reads `workspace.bronze.dados_files`;
- writes `workspace.silver.tb_usuario`.

**Testing**: dry run, then [quickstart.md](quickstart.md), compared with counts computed
directly on bronze. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`, profile
`databricks-free`

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: the first update loads about 956,000 candidate users in one
triggered run. An update with no new data writes 0 rows

**Constraints**:
- one flow per source, no `UNION`;
- every reference key is defined once;
- silver is streaming only;
- no refresh of existing tables;
- Free Edition quota: about 4 minutes between updates, and the warehouse must never be
  stopped while queries are still running on it.

**Scale/Scope**:
- 5 SQL files: 4 views and 1 table with 2 flows;
- 3 expectations;
- 3 documentation updates;
- 941,234 rows expected on 2026-10-18.

Nothing is marked NEEDS CLARIFICATION. The data facts of 2026-10-18 are in
[research.md](research.md):
- both keys are unique today;
- sex `X` appears only in the API (15,015);
- emails without `@` appear only in the API (30,190);
- every age casts to an integer.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.7.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | The files source is read only through the boundary view `vw_bronze_dados_files`, which excludes `source_file_name` and `_rescued_data` and does nothing else. API users come from silver (`vw_silver_eventos_api`), so there is no zone change. `tb_usuario` carries `quality = silver` and neither lineage column. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Five `.sql` files in current syntax (`CREATE FLOW ... AS INSERT INTO ... BY NAME`). No `APPLY CHANGES`, `LIVE` or `CREATE OR REPLACE`. |
| III. Data Quality Through Expectations | Yes | PASS | Three named expectations on `tb_usuario`: one `DROP ROW`, two warn. Null handling is explicit in each. No subqueries or UDFs. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | `check_sexo_usuario` uses the **declared exclusion** case of v1.7.0. It is a conformed table's own rule, not a validation table's. This plan names it, and the reason is the owner's choice to show a drop without quarantine on a two-source table; `X` is a generator artifact (research, Decision 5). The failed count records the rows, and `doc/pipeline-reference.md` lists it. The files source has no rejection rules, so it has no validation table or quarantine yet. |
| V. Dataset Types and Flows | Yes | PASS | Silver is streaming: four views over `STREAM(...)` and a streaming table. Two sources feed one table through one append flow each (`INSERT INTO ... BY NAME`), with no `UNION`. No `AUTO CDC`, so the change-feed rules do not apply. No layout clause. Files `06_`–`10_` continue the zone's numbering; `10_tb_usuario.sql` holds the target with its two flows. |
| VI. Record Source and Hash Keys | Yes | PASS | `origem` is a literal per flow (`API`, `ARQUIVO`); `data_carga` is set. The API key is reused from `vw_silver_eventos_api`. The files key is `md5` over `nome_empresa` and `nome_funcionario`, cast and `coalesce`d and joined with `'\|\|'`, defined once in `vw_silver_vendas_arquivo`. A not-null expectation is declared. Uniqueness holds because each key occurs once in both sources; the table does not legitimately receive a key twice, so no deduplication is required, and uniqueness is verified after each load. Business key columns go into `doc/pipeline-reference.md`. |
| VII. Kimball Dimensional Modeling | No | N/A | No gold dataset. |
| Constraints | Yes | PASS | Free Edition, serverless. Three-level names in `workspace`, with unqualified temporary views. Landing is untouched. Layout `src/pipeline/02_silver/` with `NN_`. Naming: `tb_`, `vw_`, the boundary view `vw_bronze_dados_files`, and flows `silver_tb_usuario_<source>_flow`. Synthetic data. `--profile databricks-free` on every command. |
| Workflow: skill consulted | Yes | PASS | `streaming-table-sql.md` (append flows into one target); for the first design, `auto-cdc-sql.md` and the `AUTO CDC INTO` reference page (several flows on an SCD type 1 target need the same keys and `SEQUENCE BY` type; expectations use the normal `CONSTRAINT` clause). |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: three expectations in the data quality tab. 3: candidates = rows + declared exclusion, per source. 4: `origem` populated, key unique and not null. 5: no fact. 6: documentation. |
| Workflow: full refresh | Yes | PASS | New datasets only. |

**Gate result (pre-research)**: PASS, with one deviation to justify (Principle V delete
condition, first design).

**Gate result (post-design, revised)**: PASS, no deviations. Replacing `AUTO CDC` with
append flows removed the delete-condition deviation.

## Project Structure

### Documentation (this feature)

```text
specs/006-silver-tb-usuario/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── silver-tb-usuario.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    └── 02_silver/
        ├── 01_ … 05_                         # unchanged (features 004, 005)
        ├── 06_vw_bronze_dados_files.sql      # NEW: boundary view of the files source
        ├── 07_vw_silver_vendas_arquivo.sql   # NEW: shared files view + usuario_uuid (files)
        ├── 08_vw_silver_usuario_api.sql      # NEW: API users in the target's shape
        ├── 09_vw_silver_usuario_arquivo.sql  # NEW: files users in the target's shape
        └── 10_tb_usuario.sql                 # NEW: target, 3 expectations, 2 append flows

doc/
├── pipeline-reference.md   # CHANGED: tb_usuario as built; the files views; key business columns; declared exclusion
├── architecture.md         # CHANGED: graph (files path through the boundary and shared views; two flows into S3); features table (two append flows into one target)
└── README.md               # CHANGED: layout lists 06_–10_, dataset count
```

**Structure Decision**: the five files continue `02_silver/` in reading order: the files
source path first (`06`, `07`), then the two shaping views (`08`, `09`), then the target
with its flows (`10`). The pipeline's glob covers them, so its settings do not change.

## Design Notes for Implementation

- **Shaping views have identical schemas.** Both list the same 10 columns, in the same
  order and with the same types, with `empresa_usuario` typed as STRING in the API view.
  Each flow is then a plain `SELECT *`.
- **The target is declared before its flows**, in the same file, with only the
  constraints. If the dry run rejects constraints without a column list, add the 10
  typed columns (contract fallback).
- **No `UNION`, no recomputed keys.** The API key comes from `vw_silver_eventos_api`; the
  files key from `vw_silver_vendas_arquivo`, which later sales tables will reuse.
- **Header comments in Portuguese.** In `10_tb_usuario.sql`, they state the two sources
  and their append flows, that uniqueness is verified, the drop rule as a declared
  exclusion, and the informative email rule.
- **Quota**: one upload, one dry run, one update. Don't run validation queries
  concurrently with a warehouse stop.
- **Documentation**:
  - In `doc/pipeline-reference.md`, rewrite `### tb_usuario` as built, add the two files
    views and two shaping views to `### Temporary views`, list both keys' business
    columns, and add the declared exclusion to the reconciliation.
  - In `doc/architecture.md`, route `B2 --> vw_bronze_dados_files --> vw_silver_vendas_arquivo`
    and both shaping views into `S3`, and add the feature row "two append flows into one
    table, one per source".
  - In `doc/README.md`, list `06_`–`10_` and update the dataset count.

## Complexity Tracking

No violations to justify. The first design's deviation, `AUTO CDC` without a delete
condition, disappeared when the owner replaced `AUTO CDC` with append flows on
2026-10-18.
