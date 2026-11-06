# Implementation Plan: Gold User Dimension

**Branch**: `009-gold-dim-usuario` | **Date**: 2026-10-28, revised 2026-11-04 and 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-gold-dim-usuario/spec.md`

**Note**: Revised on 2026-11-04 by the owner's direction to rebuild the dimension with
`AUTO CDC` (tasks.md, Phase 9). It replaces the materialized view of the first version.

## Revision 2026-11-05: inferred users

**Undone 2026-11-06 (owner).** The inferred-users revision below was implemented (update
`4d2eebb5`) and then reverted. The view `vw_gold_dim_usuario_tb_venda` and the flow
`gold_dim_usuario_tb_venda_flow` were removed, and the gold files are back to `01_`–`07_`. A full
refresh of `dim_usuario` only (update `8d27cdf5`, approved by the owner) cleared the 4,362
placeholder rows. `dim_usuario` is back to 941,236 rows with unchanged keys. The text that follows
is kept as history.


Spec FR-013 (owner, 2026-11-05) adds an inferred row for every user that sales reference
and silver lacks: 4,362 today. With them, every sale's user has a row, so `fato_venda` can
inner-join `dim_usuario` (constitution v3.1.0, Principle V).

Approach (research, Decisions 10–13):
- **View** `vw_gold_dim_usuario_tb_venda`, over `STREAM(silver.tb_venda)` with a
  stream-static anti join to `silver.tb_usuario`. It emits each missing user in the users
  flow's shape: the same key expression, `Desconhecido` labels, `origem` from the sale, and
  sequence `1900-01-02`.
- **Flow** `gold_dim_usuario_tb_venda_flow`, a third `AUTO CDC` flow into `dim_usuario` with
  the same keys and SCD type 1. A real row later replaces an inferred one under the same key.
- **Renumbering**: the gold files are renumbered so that the new view sits just before
  `dim_usuario` (`03_dim_usuario.sql`), and every later file shifts by one.
- **No refresh**: no full refresh or drop. `dim_usuario` grows to 945,598 rows, and existing
  keys and `data_carga` stay unchanged.

The sections below are updated for this revision; the history of the first two versions is
in research.md and tasks.md.

## Summary

Build `workspace.gold.dim_usuario`, the first gold dataset: one row per silver user plus
an "unknown" and a "not applicable" member, SCD type 1, with a surrogate key that can
never be reassigned.

Technical approach, from [research.md](research.md): a plain temporary view reads
`STREAM(workspace.silver.tb_usuario)` and computes
`sk_usuario = xxhash64(usuario_uuid) & 9223372036854775807`. An `AUTO CDC` flow applies it
to a streaming table, keyed on `usuario_uuid` and sequenced by silver's `data_carga`. A
one-time `AUTO CDC ... FROM SNAPSHOT` flow adds the two members, with fixed keys `-1` and
`-2`. The dimension declares no expectations.

## Technical Context

**Language/Version**: SQL for Lakeflow Spark Declarative Pipelines, current syntax
(`CREATE OR REFRESH STREAMING TABLE`, `CREATE TEMPORARY VIEW`, `CREATE FLOW ... AS AUTO CDC
INTO`)

**Primary Dependencies**: Lakeflow Spark Declarative Pipelines (serverless, channel
`CURRENT`); Unity Catalog; Databricks CLI

**Storage**:
- reads `workspace.silver.tb_usuario` (feature 006), streaming;
- writes `workspace.gold.dim_usuario`.

**Testing**: dry run, then [quickstart.md](quickstart.md), including a stability check
across two updates. No test framework

**Target Platform**: Databricks Free Edition, pipeline `lakeflow_dataslight_dev`
(`8d51ac7a-02be-4ce2-8afd-f4f263e448dd`), profile `databricks-free`, triggered mode. The
pipeline's source glob is `.../src/pipeline/**`, so `03_gold/` needs no settings change

**Project Type**: data pipeline (project code under `src/pipeline/`)

**Performance Goals**: 941,236 rows on the first load; later updates process only new
silver rows

**Constraints**:
- Principle V: a gold dataset fed by a change feed is a streaming table;
- Principle VII: a single-column surrogate key that keeps its value across updates; a
  mechanism that can reassign keys MUST NOT be used;
- identity columns are not supported on `AUTO CDC` targets;
- changing the existing materialized view to a streaming table requires dropping it, with
  the owner's explicit approval;
- Free Edition quota: about 4 minutes between updates.

**Scale/Scope**: 3 SQL files for `dim_usuario` in `03_gold/` (1 new); 3 flows; no
expectations; six later gold files renamed; 4 documentation updates; 941,234 + 4,362 + 2 =
945,598 rows.

Nothing is marked NEEDS CLARIFICATION.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0; re-checked for the 2026-11-05 revision against
v3.1.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Gold reads silver only (`tb_usuario`). No boundary view: silver tables carry no bronze lineage column (research, Decision 6). `quality = gold`. |
| II. SQL-Only Declarative Pipelines | Yes | PASS | Two `.sql` files in the pipeline, with no imperative statement. |
| III. Data Quality Expectations on Request | Yes | PASS | The spec requests no expectation, so none is declared (FR-008). Keys are verified by query after a load. |
| IV. Quarantine, Never Silently Discard | Yes | PASS | No rule drops a row. The dimension does not re-apply silver's rules. |
| V. Dataset Types and Flows | Yes | **DEVIATION** | Streaming table with `AUTO CDC`, SCD type 1 declared. No delete condition: see Complexity Tracking. No layout clause. Files `01_vw_gold_dim_usuario_tb_usuario.sql` and `02_dim_usuario.sql`. |
| VI. Record Source and Hash Keys | Yes | PASS | `usuario_uuid` is carried unchanged; `origem` is carried from silver. |
| VII. Kimball Dimensional Modeling | Yes | PASS | Denormalized, references no dimension. Surrogate key `sk_usuario`, single column, deterministic from the business key, so it cannot change on refresh (Decision 2). Business key `usuario_uuid` retained. **SCD type 1** declared. "Unknown" (`-1`) and "not applicable" (`-2`) members. Grain: one user. **2026-11-05**: inferred users keyed by the same expression (Principle VI, one expression per key); a real row replaces an inferred one under the same key. |
| V (v3.1.0): fact lookups | Yes | PASS (enables) | Inferred users give `dim_usuario` full coverage of sales' users, proven by an anti join returning 0 rows (quickstart). That is the condition for `fato_venda` to inner-join it. The view reads `tb_venda` as a stream (append-only) and `tb_usuario` static. |
| Constraints | Yes | PASS | Three-level name; `dim_` prefix; `sk_`, `_uuid`, `origem`, `data_carga`; flows named `gold_dim_usuario_tb_usuario_flow` and `gold_dim_usuario_membros_flow`; `--profile databricks-free`; no AI Functions. |
| Workflow: target graph | Yes | **DEVIATION** | The diagram shows `S3 (tb_usuario) → G1 (dim_usuario)`, without the flow views. **2026-11-05**: adds `S4 (tb_venda) → G1` through `vw_gold_dim_usuario_tb_venda`, a flow view Principle V requires; `doc/architecture.md` draws the edge. See Complexity Tracking. |
| Workflow: skill consulted | Yes | PASS | `databricks-pipelines`: `auto-cdc-sql.md`, `streaming-table-sql.md`. The Databricks `AUTO CDC` and limitations pages, for snapshot flows and identity columns. |
| Workflow: completion gates | Yes | DONE | 1: dry run and update. 2: no expectation declared, so nothing to show. 3: rows = silver users + 2. 4: n/a (no silver change). 5: no fact. 6: documentation. |
| Workflow: full refresh, table drop | Yes | DONE | The owner approved dropping the earlier materialized view (T025). A full refresh of `dim_usuario` only needs the owner's approval (T039). |

**Gate result (post-design, 2026-11-04)**: PASS, with the two deviations recorded below.

## Project Structure

### Documentation (this feature)

```text
specs/009-gold-dim-usuario/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── gold-dim-usuario.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
└── pipeline/
    ├── 01_bronze/ …                 # unchanged
    ├── 02_silver/ …                 # unchanged
    └── 03_gold/
        ├── 01_vw_gold_dim_usuario_tb_usuario.sql   # flow view, computes the key (unchanged)
        ├── 02_vw_gold_dim_usuario_tb_venda.sql     # NEW 2026-11-05: inferred users from sales
        ├── 03_dim_usuario.sql                      # RENAMED from 02_; adds the third flow
        ├── 04_dim_codigos.sql                      # RENAMED from 03_ (content unchanged)
        ├── 05_vw_gold_dim_curso_dados_database.sql # RENAMED from 04_
        ├── 06_vw_gold_dim_curso_membros.sql        # RENAMED from 05_
        ├── 07_dim_curso.sql                        # RENAMED from 06_
        └── 08_fato_venda.sql                       # RENAMED from 07_

doc/
├── pipeline-reference.md   # CHANGED: ### dim_usuario as built; intro
├── architecture.md         # CHANGED: features table
├── README.md               # CHANGED: layout and dataset count
└── known-issues.md         # CHANGED: identity-key item
```

`src/pipeline/03_gold/01_dim_usuario.sql`, the first version's materialized view, is
removed from the repository and from the workspace.

**Structure Decision**: Principle V places a flow view in its own file, numbered just
before the target's file. The pipeline's glob already covers both.

## Design Notes for Implementation

- **Flow view**: computes `sk_usuario` and the gold `data_carga`, and renames silver's
  `data_carga` to `data_carga_silver`, because a flow cannot compute columns and the
  sequence column must not reach the target.
- **Users flow**: `KEYS (usuario_uuid)`, `SEQUENCE BY data_carga_silver`, `COLUMNS * EXCEPT
  (data_carga_silver)`, `STORED AS SCD TYPE 1`.
- **Members flow**: `AUTO CDC ONCE ... FROM SNAPSHOT` with `WITH VERSION` fixed at
  `TIMESTAMP'1900-01-01'` (research, Decision 8).
- **The target has no column list**: the flows define its schema, as in `tb_curso`.
- **Header comments in Portuguese**: grain, SCD type 1, how the key is computed and why it
  is not an identity column, the two members and their keys, and that facts resolve
  `sk_usuario` by joining on `usuario_uuid` and fall back to `-1`.
- **Inferred users (2026-11-05)**:
  - view `vw_gold_dim_usuario_tb_venda`:
    `STREAM(workspace.silver.tb_venda) AS v LEFT JOIN workspace.silver.tb_usuario AS u`,
    with `WHERE u.usuario_uuid IS NULL AND v.usuario_uuid IS NOT NULL`;
  - columns in the users view's order: `Desconhecido` labels, `CAST(NULL AS INT)` for age,
    `v.origem`, `current_timestamp()`, and `TIMESTAMP'1900-01-02' AS data_carga_silver`;
  - flow `gold_dim_usuario_tb_venda_flow`, with the users flow's clauses;
  - Portuguese comments explaining Kimball's inferred member, why the sequence is
    1900-01-02 (newer than the snapshot's 1900-01-01, older than any silver row), and that
    a real row replaces it.
- **Renaming**:
  - delete the six old file names from the workspace before uploading;
  - confirm all eight gold files are identical in the workspace;
  - update every link in `doc/`.
- **Proof**: a real update, not only a dry run (contract). If it fails, stop and ask the
  owner.
- **Quota**: about 4 minutes between updates.

## Complexity Tracking

| Deviation | Why it is needed | Simpler alternative rejected |
|---|---|---|
| Principle V: no delete condition on the `AUTO CDC` flow | `silver.tb_usuario` is append-only and delivers no delete event, so no condition can be true | `APPLY AS DELETE WHEN false`: satisfies the wording and documents nothing |
| Workflow: a second flow view the diagram does not draw (2026-11-05), `vw_gold_dim_usuario_tb_venda` | An `AUTO CDC` flow cannot compute columns, and the inferred users must be shaped like the users flow; `doc/architecture.md` draws the new `tb_venda → dim_usuario` edge | Inferred users in silver: they are a dimension concept, and silver keeps only accepted users |
| Workflow: a flow view the diagram does not draw | An `AUTO CDC` flow reads only a named source and cannot compute columns, and the key and gold `data_carga` must be computed somewhere | Computing the key in silver: it would change `silver.tb_usuario`, outside this feature's scope, and a surrogate key belongs to the dimension |
