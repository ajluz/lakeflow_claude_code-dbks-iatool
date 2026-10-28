# Implementation Plan: Silver Sales Table from API Events and Partner Files

**Branch**: `007-silver-tb-venda` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-silver-tb-venda/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Build `workspace.silver.tb_venda` from two sources: valid API events that carry a
payment, and the partner companies' sales files. Each row has a deterministic sale key
(`venda_uuid`), the access, user and course keys that the existing silver tables already
use, the payment method and installments, and three amounts (installment, paid,
discount) as `DECIMAL(9,2)`. All five rules only count; no row is dropped.

Technical approach, from [research.md](research.md): three SQL files under
`src/pipeline/02_silver/`, matching the diagram's `V3`, `V4` and `S4`.
- **`09_vw_silver_tb_venda_api.sql`**: flow view over the valid side of
  `temp_tb_validacao_api`, events with a payment, in the table's 13 columns. An inner
  query names `timestamp_acesso`, `endereco_ip_acesso` and `local_acesso` so that
  `acesso_uuid` is written character for character as in `05_tb_acesso.sql`.
- **`10_vw_silver_tb_venda_files.sql`**: flow view over `vw_bronze_dados_files`, in the
  same 13 columns.
- **`11_tb_venda.sql`**: the streaming table with five warn expectations and two append
  flows, each `SELECT * FROM STREAM(<flow view>)`.

The spec's five decisions are taken as accepted: the owner moved to planning after they
were presented on 2026-10-28.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE TEMPORARY VIEW`, `CREATE OR REFRESH STREAMING TABLE`,
`CREATE FLOW ... AS INSERT INTO ... BY NAME`, `CONSTRAINT ... EXPECT`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless), two append
flows on one target; Unity Catalog; Databricks CLI v1.11.0

**Storage**:
- reads `workspace.silver.temp_tb_validacao_api` (feature 004), valid side;
- reads `vw_bronze_dados_files` (feature 006);
- writes `workspace.silver.tb_venda`.

**Testing**: dry run, then [quickstart.md](quickstart.md), compared with counts computed
directly on bronze. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: the first update loads every existing sale in one triggered run.
An update with no new data writes 0 rows

**Constraints**:
- one flow per source, each reading a flow view (v1.9.0), no `UNION`;
- each reused key written exactly as in the table that defined it;
- silver is streaming only; no AI Functions (v1.10.0);
- no refresh of existing tables: `tb_venda` is new, so its first update is a normal one;
- Free Edition quota: about 4 minutes between updates, and the warehouse is never stopped
  while queries still run on it.
- **The `databricks-free` login expired on 2026-10-28.** The owner must run
  `databricks auth login --profile databricks-free` before research facts are measured
  and before implementation.

**Scale/Scope**:
- 3 SQL files: 2 flow views and 1 table with 2 flows;
- 5 expectations;
- 4 documentation updates (`pipeline-reference.md`, `architecture.md`, `README.md`,
  `known-issues.md`).

Nothing is marked NEEDS CLARIFICATION. Three data facts could not be measured because the
login expired; each has a fallback in [research.md](research.md) and a measuring query in
quickstart step 1:
- the name of the installment field in the bronze payload (expected `valor_parcelas`);
- the uniqueness of the API sale key (expected unique);
- the number of rows whose installments × installment value differ from the paid amount.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.10.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | The files source is read only through the existing boundary view `vw_bronze_dados_files`. API sales come from silver (`temp_tb_validacao_api`), so there is no zone change. `tb_venda` carries `quality = silver` and no lineage column. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Three `.sql` files in current syntax. No `LIVE`, `APPLY CHANGES` or `CREATE OR REPLACE`. |
| III. Data Quality Through Expectations | Yes | PASS | Five named warn expectations on `tb_venda`. Each states how it treats `NULL`. No subqueries, UDFs or AI Functions. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a row, so there is no declared exclusion. API rows come from the valid side of the validation table; quarantined events stay in `tb_quarentena`. The files source has no rejection rules, so it has no validation table. API events without a payment are not sales; they are not discarded, because they stay in `tb_acesso`. |
| V. Dataset Types and Flows | Yes | PASS | Two flow views over `STREAM(...)` and one streaming table. Two append flows (`INSERT INTO ... BY NAME SELECT * FROM STREAM(<view>)`), no `UNION`. Flow views are named `vw_silver_tb_venda_api` and `vw_silver_tb_venda_files`, each in its own file numbered before the target's. No `AUTO CDC`, no layout clause. |
| VI. Record Source and Hash Keys | Yes | PASS | `origem` is a literal per flow (`API`, `ARQUIVO`); `data_carga` is set. `venda_uuid` is `md5` over the business columns with `concat_ws('\|\|', coalesce(cast(... AS STRING), ''), ...)`; not-null expectation; uniqueness verified after each load. `acesso_uuid`, `usuario_uuid` and `curso_uuid` reuse the existing expressions character for character, and the quickstart verifies the joins. `curso_uuid` equals the catalog identifier (the `tb_curso` exception). |
| VII. Kimball Dimensional Modeling | No | N/A | No gold dataset. `fato_venda` will declare its grain when it is built. |
| Constraints | Yes | PASS | Free Edition, serverless. Three-level names in `workspace`, unqualified temporary views. Landing untouched. Files `09_`–`11_` in `src/pipeline/02_silver/`. Naming: `tb_`, `vw_silver_tb_venda_<source>`, flows `silver_tb_venda_<source>_flow`. Synthetic data. `--profile databricks-free` on every command. AI tools: none in the pipeline. |
| Workflow: target graph | Yes | PASS | `doc/lakeflow_architecture.png` and `doc/architecture.md` show `T1 → V3 → S4` and `V2 → V4 → S4`. The three datasets are exactly `V3`, `V4` and `S4`. |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines`: `streaming-table-sql.md` (empty target plus `CREATE FLOW ... INSERT INTO ... BY NAME`; never `AS SELECT` with flows) and `expectations-sql.md` (warn expectations on the target). |
| Workflow: completion gates | Yes | PLANNED | 1: dry run and update. 2: five expectations in the data quality tab. 3: API sales = valid events with a payment; files sales = bronze file rows. 4: `origem` populated, `venda_uuid` unique and not null. 5: no fact. 6: documentation, including `known-issues.md`. |
| Workflow: full refresh, table drop | Yes | PASS | New datasets only. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations. The open flow-name finding of feature
006 (unqualified flow names appear under `workspace.bronze` in the event log) applies to
these two flows too. They follow `tb_usuario`'s form until the owner decides that finding
(research, Decision 8).

## Project Structure

### Documentation (this feature)

```text
specs/007-silver-tb-venda/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── silver-tb-venda.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    └── 02_silver/
        ├── 01_ … 08_                          # unchanged (features 004–006)
        ├── 09_vw_silver_tb_venda_api.sql      # NEW: flow view, valid API events with a payment
        ├── 10_vw_silver_tb_venda_files.sql    # NEW: flow view, partner sales files
        └── 11_tb_venda.sql                    # NEW: target, 5 expectations, 2 append flows

doc/
├── pipeline-reference.md   # CHANGED: tb_venda as built; the two flow views; venda_uuid business columns
├── architecture.md         # CHANGED: features table points to 11_tb_venda.sql
├── README.md               # CHANGED: layout lists 09_–11_, dataset count
└── known-issues.md         # CHANGED: wrong paid amount and silver key mismatch resolved
```

**Structure Decision**: the three files continue `02_silver/` in reading order, API view,
files view, target, as Principle V requires (flow views numbered just before the
target). The pipeline's glob covers them, so its settings do not change.

## Design Notes for Implementation

- **Flow views have identical schemas.** Both list the same 13 columns, in the order of
  the data model, with the same types. `acesso_uuid` is `CAST(NULL AS STRING)` in the
  files view.
- **Reused keys, character for character.** The API view's inner query computes
  `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso`, then `acesso_uuid`,
  `usuario_uuid` and `curso_uuid`, copied from `05_tb_acesso.sql`. The files
  `usuario_uuid` is copied from `07_vw_silver_tb_usuario_files.sql`.
- **Decimal arithmetic.** The discount is cast to `DECIMAL(5,2)` before it is multiplied
  or turned into text, and the list price is parsed to `DECIMAL(9,2)`. Products of two
  decimals are cast back to `DECIMAL(9,2)`.
- **The target is declared before its flows**, in the same file, with only the
  constraints, as `tb_usuario` is.
- **Header comments in Portuguese.** They name the two sources and their flows, say that
  no rule drops rows, that `acesso_uuid` is empty for corporate sales, and that the keys
  reuse the expressions of `tb_acesso` and `tb_usuario`.
- **Quota**: one upload, one dry run, one update, then the no-new-data update.
- **Documentation**:
  - In `doc/pipeline-reference.md`, rewrite `### tb_venda` as built, mark the two flow
    views as built in `### Temporary views`, list `venda_uuid`'s business columns, and
    add the reconciliation.
  - In `doc/architecture.md`, point the features-table row "Multiple append flows into
    one table" to `11_tb_venda.sql`.
  - In `doc/README.md`, list `09_`–`11_` and update the dataset count.
  - In `doc/known-issues.md`, remove "File sales get a wrong paid amount", and reduce
    "Sales missing from fato_venda" to its gold part: the silver key mismatch and the
    empty discount are fixed.

## Complexity Tracking

No violations to justify.
