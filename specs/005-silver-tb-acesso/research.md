# Research: Silver Access Table from API Events

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

Sources consulted: constitution v1.7.0, the `databricks-pipelines` skill
(`references/streaming-table-sql.md`, `references/expectations-sql.md`,
`references/temporary-view-sql.md`), feature 004's contract
(`specs/004-api-quarantine/contracts/silver-validation-quarantine.md`), the generator in
`explorations/functions.py`, the earlier pipeline's description of `tb_acesso` in
`doc/pipeline-reference.md`, and queries on the workspace (profile `databricks-free`)
on 2026-10-18.

## Facts established

All counts are over the **valid** API events: the bronze events that pass feature 004's
three rules, which is what `tb_acesso` reads.

| Fact | Value |
|---|---|
| Valid events | 2,541,715 |
| `access_point` values | `iphone` 765,300; `android` 510,200; `chrome` 510,185; `firefox` 382,635; `safari` 255,090; `unknown` 118,305. All lowercase, no nulls |
| `access_date` | STRING in ISO-8601 with `Z`, e.g. `2024-06-01T00:00:00.000Z`; range 2024-06-01 to 2024-06-03; 0 nulls; 0 values that `try_to_timestamp` cannot read |
| `ip_address = '999.999.999.999'` | 25,523 (about 1%); 0 null addresses |
| Events without a user (`payload.info_usuario.nome` null) | 1,785,466 |
| Events without a product (`payload.info_produto.product_name` null) | 2,321,243 |
| Product names | 3: `Programa Data Heroes` 103,205; `Construindo um Data Lakehouse com SQL e DLT` 68,991; `Mastering SQL no Databricks` 48,276. All 3 are in the course catalog, and `md5(product_name)` equals the catalog's `curso_uuid` for each |
| `acesso_uuid` uniqueness | 2,541,715 rows, 2,517,192 distinct keys. The 24,523 repeats all come from `999.999.999.999` rows. Among the 2,516,192 rows kept, keys are **unique** (2,516,192 distinct) |
| Expected reconciliation | 2,541,715 valid = 2,516,192 in `tb_acesso` + 25,523 dropped |

## Decision 1: A shared view of valid API events defines the reference keys once

- **Decision**: a temporary view `vw_silver_eventos_api` in
  `src/pipeline/02_silver/04_vw_silver_eventos_api.sql`. It reads
  `STREAM(workspace.silver.temp_tb_validacao_api)` with `WHERE NOT fl_registro_invalido`,
  keeps the event columns, and adds `timestamp_acesso`, `usuario_uuid` and `curso_uuid`.
  `tb_acesso` reads `STREAM(vw_silver_eventos_api)`.
- **Rationale**: Principle VI ("One definition per key") requires the expression of a hash
  key to be written once, "in the dataset that owns the entity or in a shared temporary
  view". `tb_acesso` owns the access, but not the user or the course. Later tables built
  from API events (users, sales) need the same `usuario_uuid` and `curso_uuid`. Putting
  them, and `timestamp_acesso` they depend on, in a shared view gives every consumer one
  definition. The view also encodes feature 004's consumer rule once.
- **Streaming**: the view reads `STREAM(...)`, as v1.7.0 requires for silver (Principle V).
  It is not a boundary view: it stays inside silver, so it keeps the name `vw_` +
  description, not `vw_<zone>_<dataset>`.
- **Alternatives considered**: computing the keys inside `tb_acesso`. Rejected: the next
  user or sales table would recompute them, which Principle VI forbids. A private
  streaming table instead of the view. Rejected: nothing is gained by materializing, and
  Principle V defaults intermediate logic to a temporary view.

## Decision 2: The key expressions

| Key | Owner | Expression | When empty |
|---|---|---|---|
| `acesso_uuid` | `tb_acesso` | `md5(concat_ws('\|\|', coalesce(cast(timestamp_acesso AS STRING), ''), coalesce(endereco_ip_acesso, ''), coalesce(local_acesso, '')))` | never: `md5` of a non-null string |
| `usuario_uuid` | `vw_silver_eventos_api` | `CASE WHEN payload.info_usuario.nome IS NOT NULL THEN md5(concat_ws('\|\|', coalesce(cast(timestamp_acesso AS STRING), ''), payload.info_usuario.nome)) END` | null when the event has no user |
| `curso_uuid` | `vw_silver_eventos_api` | `CASE WHEN payload.info_produto.product_name IS NOT NULL THEN md5(payload.info_produto.product_name) END` | null when the event has no product |

- **Rationale**: Principle VI requires `md5` over business key columns only. Each
  component is cast to `STRING`, `NULL` is replaced by a fixed placeholder (`''`), and the
  components are joined with a delimiter (`'||'`). Bare `concat` is not used. A reference
  key is null when the referenced entity is absent (spec, Assumptions). The placeholder
  rule applies to the components of a key that exists.
- `curso_uuid` is a single-column key. The source delivers the course identifier as
  `md5(nome_curso)`, and Principle VI's `tb_curso` exception requires referencing tables to
  "produce a value equal to the identifier delivered by the source". `md5(product_name)`
  does, as verified for all 3 courses. So no `concat_ws`, which would change the value.
- `ip_address` in the request's `acesso_uuid` is `endereco_ip_acesso`, the same value.
- **Alternatives considered**: `uuid()`. Rejected: it is random, so reprocessing would
  change every key (Principle VI).

## Decision 3: Column derivations

| Column | Expression | Notes |
|---|---|---|
| `timestamp_acesso` | `try_to_timestamp(access_date)` | ISO-8601 text parses without a format. `try_` returns null instead of failing the update; 0 such values today, measured by `check_timestamp_acesso` |
| `endereco_ip_acesso` | `ip_address` | unchanged |
| `local_acesso` | `CASE WHEN lower(access_point) IN ('iphone', 'android') THEN 'Mobile' WHEN lower(access_point) IN ('chrome', 'safari', 'firefox') THEN 'Computador' ELSE 'unknown' END` | `lower` covers casing (spec edge case). Null falls to `unknown` |
| `origem` | `'API'` | literal, set by the flow that reads the source (Principle VI) |
| `data_carga` | `current_timestamp()` | load time of the row |

`timestamp_acesso` is computed in the view, because `usuario_uuid` depends on it.
`local_acesso` and `acesso_uuid` are computed in `tb_acesso`, which owns the access.

## Decision 4: The four expectations and their actions

| Name | Condition | Action | Why |
|---|---|---|---|
| `check_endereco_ip_acesso` | `endereco_ip_acesso IS NULL OR endereco_ip_acesso != '999.999.999.999'` | `ON VIOLATION DROP ROW` | the request. A declared exclusion under Principle IV (v1.7.0): the rows are not quarantined, by the owner's decision |
| `check_local_acesso` | `local_acesso != 'unknown'` | warn | the request: informative only |
| (commented) `check_local_acesso` | same | `ON VIOLATION FAIL UPDATE` | the request: kept as a comment on the line after the active rule, ready to swap in |
| `check_timestamp_acesso` | `timestamp_acesso IS NOT NULL` | warn | measures the spec's "unreadable access time" edge case instead of dropping silently |
| `check_acesso_uuid` | `acesso_uuid IS NOT NULL` | warn | Principle VI requires a not-null expectation on the hash key |

- **Null handling** (Principle III): the address rule passes on null (spec FR-011).
  `local_acesso` is never null, because the mapping's `ELSE` covers it. The other two test
  for null directly.
- **Swapping the commented rule**: comment out the warn line and uncomment the
  `FAIL UPDATE` line. Both have the same name, so only one may be active.
- **Declared exclusion, the reason Principle IV asks for**: the owner wants the talk to
  show each expectation action once (spec, User Story 2). The impossible address is a
  generator artifact with no analytical value. Its 25,523 rows remain in bronze, and the
  rule's failed count records them.
- **Alternatives considered**: `FAIL UPDATE` on the key. Rejected: Principle III reserves it
  for keys of gold dimensions, and the key cannot be null by construction.

## Decision 5: No deduplication

- **Decision**: `tb_acesso` does not deduplicate. Uniqueness of `acesso_uuid` is verified
  after each change (quickstart), as Principle VI requires.
- **Rationale**: all repeated keys in the current data belong to rows the address rule
  drops. The rows kept have unique keys.
- **Risk**: a future batch where two real accesses share time, address and device category
  would break uniqueness. The quickstart check catches it. The fix would be a dedup on
  `acesso_uuid` or `AUTO CDC` keyed on it (Principle VI), planned as a change.

## Decision 6: Files, numbering and rollout

- **Files**: `src/pipeline/02_silver/04_vw_silver_eventos_api.sql` and
  `src/pipeline/02_silver/05_tb_acesso.sql`, numbered after feature 004's three files, in
  reading order.
- **Rollout**: both datasets are new. Upload, dry run, normal update. No refresh of any
  existing table, so no approval is needed. Free Edition quota: stop the SQL warehouse and
  wait about 4 minutes after the previous update.
- **Lesson from feature 004**: if the first real update fails after creating
  `tb_acesso`'s backing table, and its columns change before any successful run, ask the
  owner to refresh `tb_acesso` alone rather than expecting a normal update to fix the
  schema.
