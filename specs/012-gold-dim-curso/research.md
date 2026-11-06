# Research: Gold Course Dimension (SCD Type 2)

**Feature**: [spec.md](spec.md) | **Date**: 2026-11-05

Sources:
- constitution v2.0.0;
- `databricks-pipelines` skill: `auto-cdc-sql.md` (SCD type 2, `__START_AT` / `__END_AT`,
  `TRACK HISTORY`, snapshot flows), `scd-2-querying.md`;
- feature 008 (`tb_curso`: key, sequence, delete condition, the feed view);
- feature 009 (`dim_usuario`: the flow view, the key expression, members by
  `AUTO CDC ONCE ... FROM SNAPSHOT`);
- the earlier pipeline's `code_tips/03_gold/02_dim_curso.sql` (git history);
- `doc/known-issues.md`; the workspace on 2026-11-05.

No item of the Technical Context was left as NEEDS CLARIFICATION.

## Decision 1: One streaming table fed by `AUTO CDC ... STORED AS SCD TYPE 2`

- **Decision**: `workspace.gold.dim_curso` is a streaming table, target of the flow
  `gold_dim_curso_flow`:
  - `AUTO CDC INTO workspace.gold.dim_curso FROM STREAM(vw_gold_dim_curso_dados_database)`;
  - `KEYS (curso_uuid)`;
  - `APPLY AS DELETE WHEN change_type = 'delete'`;
  - `SEQUENCE BY timestamp_change`;
  - `COLUMNS * EXCEPT (change_type, timestamp_change)`;
  - `STORED AS SCD TYPE 2`.
- **Rationale**:
  - The platform's SCD type 2 mechanism keeps history in `__START_AT` / `__END_AT`, the
    names the owner chose (spec, Clarifications).
  - A change feed in gold is a streaming table (Principle V).
  - Key, sequence and delete condition are those of `silver_tb_curso_flow`, as the course
    feed exception requires (Principle I, FR-004).
  - A delete closes the current version (`__END_AT` set) and removes nothing (FR-005).
- **Alternatives considered**:
  - A silver SCD 2 table under a gold materialized view, which would allow the names
    `start_at`/`end_at` (rejected by the owner).
  - Reading `silver.tb_curso`: it keeps no history (Principle I exception).

## Decision 2: A flow view computes the surrogate key

- **Decision**: a temporary view `vw_gold_dim_curso_dados_database`, in its own file
  numbered just before the target's. It reads `STREAM(vw_bronze_tb_curso)` and selects:
  - `sk_curso`;
  - `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso`, `data_carga`;
  - `change_type`, `timestamp_change`.

  It has no filter and no other expression. The `AUTO CDC` flow excludes the two control
  columns.
- **Rationale**:
  - An `AUTO CDC` flow reads a view by name and cannot compute columns, so the key is
    computed before it. This is the `dim_usuario` pattern (feature 009).
  - The explicit column list leaves out `processing_time` and `origem` (owner, spec
    Clarifications). Those two columns therefore never reach the flow.
  - Deriving a surrogate key is not cleansing or a business rule on the feed. Every row of
    the feed passes unchanged in its course attributes (Principle I exception).
  - Name: `vw_<zone>_<target>_<source>` (Principle V), where the source is the bronze
    dataset `dados_database`. `tb_curso` would wrongly suggest it reads silver.
- **Alternatives considered**:
  - Selecting `*` from the feed view and excluding the columns in the flow: this works
    too, but the view would then not produce the target's columns. Principle V asks flow
    views to produce exactly the target's columns.
  - Adding the key to `vw_bronze_tb_curso`: its exception is bounded and allows no new
    column (Principle I).

## Decision 3: The key, one per version

- **Decision**: `sk_curso = xxhash64(curso_uuid, timestamp_change) & 9223372036854775807`.
- **Rationale**:
  - A version is opened by one change event, identified by the course and the change time.
  - The key is deterministic, so it is the same after any recomputation or full refresh
    (FR-006).
  - When an update opens a new version, that version carries its own key. The previous
    version keeps the one it had: `AUTO CDC` only sets the old version's `__END_AT`.
  - The mask clears the sign bit, so only members are negative.
  - The three initial courses share one change time, but their identifiers differ, so their
    keys differ.
  - It is the `dim_usuario` expression, with the change time added.
- **Collisions**: 64 bits over a handful of rows. Uniqueness and positivity are checked by
  query.
- **Alternatives considered**:
  - Identity: not supported on `AUTO CDC` targets (`doc/known-issues.md`).
  - `xxhash64(curso_uuid)`: one key for every version of a course, which breaks
    "one surrogate key per version" (Principle VII).
  - A hash of the attribute values: two versions with the same values (a price reverted)
    would collide.

## Decision 4: Every change event opens a version (no `TRACK HISTORY`)

- **Decision**: the flow declares no `TRACK HISTORY ON`. Every insert or update event
  opens a new version.
- **Rationale**:
  - `sk_curso` and `data_carga` differ on every event. With
    `TRACK HISTORY ON nome_curso, nivel_curso, valor_curso`, an update that repeats the
    current values would overwrite those untracked columns in place. That reassigns the
    current version's key, which Principle VII forbids.
  - Without the clause, an update with no effect simply opens another version. All keys are
    kept, and the history records that the source sent a change (spec, Edge Cases).
  - The generator never sends such an update.
- **Alternatives considered**: `TRACK HISTORY ON` the three attributes, rejected because
  it can change a key.

## Decision 5: Members through a one-time SCD 2 snapshot flow

- **Decision**: `gold_dim_curso_membros_flow`, built the same way as `dim_usuario`'s:
  - `AUTO CDC ONCE INTO workspace.gold.dim_curso FROM SNAPSHOT (...)`, with two rows:
    - `-1`: `curso_uuid '-1'`, `Desconhecido` in name and level;
    - `-2`: `curso_uuid '-2'`, `Não se aplica` in name and level;
    - in both rows, `valor_curso` is `CAST(NULL AS DECIMAL(9,2))` and `data_carga` is
      `current_timestamp()`;
  - `WITH VERSION (SELECT TIMESTAMP'1900-01-01' AS versao WHERE NOT EXISTS (SELECT 1 FROM last_snapshot_version()))`;
  - `KEYS (curso_uuid)`;
  - `STORED AS SCD TYPE 2`.
- **Rationale**:
  - The flow view stays a plain `SELECT` (owner's preference in feature 009).
  - The version is a `TIMESTAMP`, the type of `SEQUENCE BY`, so the members'
    `__START_AT` is 1900-01-01: they are valid for any fact date. They are never closed,
    because no later snapshot runs (`ONCE`).
  - A snapshot treats keys absent from it as deleted at its version. 1900 is older than
    every course change, so no course version is closed by it.
  - The pattern works on `dim_usuario` (SCD 1). Its SCD 2 behaviour is verified at the
    first update (quickstart step 2: 3 open course rows).
- **Risk**: if the snapshot closes or alters course versions, implementation stops and
  reports to the owner before any change. A full refresh is not a fix (constitution).
- **Alternatives considered**: adding the members in the flow view, which cannot union a
  static query with a stream (Principle V forbids `UNION` across streaming sources, and a
  static branch would re-emit the members every update).

## Decision 6: Price type and `data_carga` come from the feed view unchanged

- **Decision**:
  - `valor_curso` is the feed view's `DECIMAL(9,2)`, with no cast in gold.
  - `data_carga` is the feed view's `current_timestamp()`: the time the update that read
    the change wrote the version.
- **Rationale**:
  - These are the owner's answers (spec, Clarifications).
  - No transformation of the feed is added in gold (Principle I exception).
  - When a version is closed later, only `__END_AT` changes, so `data_carga` keeps the
    write time of the version.
- **Alternatives considered**: a `current_timestamp()` in the gold view. It has the same
  value and adds an expression the exception does not need.

## Decision 7: Ties in change time

- **Decision**: `SEQUENCE BY timestamp_change` alone. A tie between two changes of one
  course is undefined, as in `tb_curso`.
- **Rationale**: the exception requires the same `SEQUENCE BY` as silver (Principle I),
  and the generator writes each change in its own run.
- **Alternatives considered**: `STRUCT(timestamp_change, ...)`, which would differ from
  silver's flow.

## Decision 8: No full refresh; update and delete are not run

- **Decision**:
  - The first ordinary update creates `dim_curso` and reads the feed from the start: a new
    streaming consumer reads all existing changes.
  - `tb_curso` is unaffected; it keeps its own checkpoint.
  - The generator's `update row` and `delete row` are not run (spec, Assumptions).
- **Rationale**: `dim_curso` does not exist in the workspace today (checked 2026-11-05),
  so nothing is dropped or refreshed.
- **Alternatives considered**: none.
