# Research: Gold User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28, revised 2026-11-04

Decisions 1, 2, 3 and 5 were replaced on 2026-11-04, when the owner directed that the
dimension use `AUTO CDC`. Decision 7 was replaced after constitution v2.0.0. Decisions 8 and
9 were added.

Sources consulted: constitution v1.11.0 (Principles I, III, V, VII; Constraints); the
`databricks-pipelines` skill (`references/materialized-view-sql.md`,
`expectations-sql.md`); feature 006 (`tb_usuario`); `doc/known-issues.md`; the pipeline's
settings; queries on the workspace (profile `databricks-free`) on 2026-10-28 and
2026-11-04; the Databricks pages
[Pipeline limitations](https://docs.databricks.com/aws/en/ldp/limitations),
[The AUTO CDC APIs](https://docs.databricks.com/aws/en/ldp/cdc) and
[CREATE FLOW](https://docs.databricks.com/aws/en/ldp/developer/ldp-sql-ref-create-flow).

## Facts established

| Fact | Value (2026-10-28) |
|---|---|
| `silver.tb_usuario` | 941,234 rows, 941,234 distinct `usuario_uuid`, none empty; `API` 741,234, `ARQUIVO` 200,000; every age present; 29,599 emails without `@` |
| Users referenced by `tb_venda` but absent from `tb_usuario` | 4,362 (their sex failed `check_sexo_usuario`) |
| Accesses without a user | 1,767,621 |
| Pipeline source | glob `.../lakeflow_dev/src/pipeline/**`; default schema `bronze`; serverless |
| `workspace.gold` | held `dim_tempo` only |
| Masked key on 2026-11-04 | 941,234 users, 941,234 distinct `xxhash64(usuario_uuid) & 9223372036854775807`, no collision; silver's `data_carga` is `TIMESTAMP`, never null |

## Decision 1: A streaming table fed by `AUTO CDC`

- **Decision**: `CREATE OR REFRESH STREAMING TABLE workspace.gold.dim_usuario`, the target of
  an `AUTO CDC` flow that reads `workspace.silver.tb_usuario` as a stream.
- **Rationale**: the owner's direction on 2026-11-04. Only new silver rows are processed on
  each update, and a repeated key overwrites the row in place, which is SCD type 1.
- **Alternatives considered**: the first version's materialized view (replaced by the
  owner's direction).

## Decision 2: `sk_usuario = xxhash64(usuario_uuid) & 9223372036854775807`

- **Decision**: the surrogate key is computed in the flow view, as a non-negative `BIGINT`.
- **Rationale**:
  - The owner asked for an identity column, but
    [identity columns are not supported on `AUTO CDC` targets](https://docs.databricks.com/aws/en/ldp/limitations).
    A community answer the owner shared reports that such a column stays null.
  - Principle VII: one column, and a value that never changes for a given user. A
    deterministic function of the business key gives the same value on every update,
    refresh and full refresh, with no state to lose.
  - The mask clears the sign bit, so negative keys mean only the members.
- **Collision risk**: with 941,236 keys in a 63-bit space, the chance of any collision is
  about 4.8 × 10⁻⁸. Measured on 2026-11-04: none. Uniqueness is verified after each load.
- **Alternatives considered**:
  - a regular Delta table with an identity column, filled by `INSERT` from the streaming
    table (Principle II forbids imperative statements, and it cannot apply updates);
  - `row_number()` or `monotonically_increasing_id()` in a downstream view (Principle VII:
    values can change);
  - an append-only key table with an identity column (more datasets, the sources disagree
    on identity in streaming tables, and a full refresh could reassign keys);
  - the `md5` string itself (FR-002 fixes `BIGINT`, and the constitution separates `sk_`
    from `_uuid`).

## Decision 3: SCD type 1 through `AUTO CDC`

- **Decision**: `KEYS (usuario_uuid)`, `SEQUENCE BY data_carga_silver`, `STORED AS SCD TYPE
  1`.
- **Rationale**: silver has no repeated key today, so the flow changes nothing now, but it
  keeps the grain if silver ever delivers a key twice: the latest silver row wins.

## Decision 4: The two members

- **Decision**:

  | Member | `sk_usuario` | `usuario_uuid` | Text attributes | `idade_usuario` |
  |---|---|---|---|---|
  | unknown | `-1` | `'-1'` | `'Desconhecido'` | null |
  | not applicable | `-2` | `'-2'` | `'Não se aplica'` | null |

  Text attributes are `nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`,
  `profissao_usuario`, `empresa_usuario` and `origem`.
- **Rationale**: Principle VII requires both members. `-1` and `-2` are the usual Kimball
  values, are readable in a fact, and cannot be a real business key: `usuario_uuid` is a
  32-character hexadecimal `md5`. The surrogate keys `-1` and `-2` could in theory equal
  an `xxhash64` value; the uniqueness check covers that too.
- **Alternatives considered**: hashing the labels (`xxhash64('Desconhecido')`), which
  makes the member keys unreadable in facts.

## Decision 5: `data_carga`

- **Decision**: `current_timestamp() AS data_carga` in the flow view, for users and members.
  Silver's `data_carga` is renamed to `data_carga_silver`, sequences the flow, and
  does not reach the target.
- **Rationale**: `AUTO CDC` writes only rows that change, so `data_carga` is the time gold
  last wrote the row (owner, 2026-11-04). It does not move on an update with no new data.
- **Alternatives considered**: a materialized view on top that stamps every row on each
  refresh (one more dataset, and a full recompute on every update).

## Decision 6: No boundary view between silver and gold

- **Decision**: the flow view reads `workspace.silver.tb_usuario` directly.
- **Rationale**: Principle I's boundary views exist to drop the bronze lineage columns,
  "because only bronze carries those columns, every read of a bronze table goes through
  such a view". Silver tables carry none of them. The diagram draws `S3 → G1` with no
  view, and the target-graph rule forbids adding one.

## Decision 7: No expectations

- **Decision**: `dim_usuario` declares no expectation.
- **Rationale**: the owner's decision on 2026-11-04. Constitution v2.0.0 allows an
  expectation only when a spec requests it, and FR-008 requests none.
- **Consequence**: a null key no longer stops the update. Quickstart step 3 verifies the keys
  by query after a load.

## Decision 8: Members through a one-time snapshot flow

- **Decision**: `AUTO CDC ONCE ... FROM SNAPSHOT` with the two members as literal rows, and
  `WITH VERSION` returning `TIMESTAMP'1900-01-01'`.
- **Why `WITH VERSION` stays**: a snapshot treats absent keys as deleted at its version. The
  1900 version is older than every silver row, so users are not deleted. The default version
  is the load time, which is newer than silver's rows.
- **Rejected attempts**:
  - `UNION ALL` in the view: Spark rejects a stream with literal rows. Dry run `d14aaf4f`
    passed and update `771c5ad8` failed, so **a dry run does not catch this**.
  - Members generated from each silver row (`explode`): worked, but it was hard to follow, and
    an empty silver meant no members.
  - A static reference table with a second flow: one more table and a setup step.
  - A materialized view over the target: one more dataset, and `dim_usuario` would no longer
    be the `AUTO CDC` target.

## Decision 9: No delete condition

- **Decision**: the flow has no `APPLY AS DELETE WHEN`, recorded as a deviation in the plan.
- **Rationale**: silver delivers no delete event. A user removed from silver keeps a row.
