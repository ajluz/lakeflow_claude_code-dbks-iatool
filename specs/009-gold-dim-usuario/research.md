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

## Revision 2026-11-05: inferred users (spec FR-013)

**Undone 2026-11-06 (owner).** The inferred-users revision below was implemented (update
`4d2eebb5`) and then reverted. The view `vw_gold_dim_usuario_tb_venda` and the flow
`gold_dim_usuario_tb_venda_flow` were removed, and the gold files are back to `01_`–`07_`. A full
refresh of `dim_usuario` only (update `8d27cdf5`, approved by the owner) cleared the 4,362
placeholder rows. `dim_usuario` is back to 941,236 rows with unchanged keys. The text that follows
is kept as history.


Sources:
- constitution v3.1.0 (Principle V: a fact may inner-join a dimension that guarantees
  coverage, proven by an anti join returning 0 rows);
- spec Clarifications, 2026-11-05;
- Databricks CDC page (a target may have exactly one `AUTO CDC FROM SNAPSHOT` flow and one or
  more `AUTO CDC` flows, SCD type 1, same keys);
- the workspace on 2026-11-05.

Facts:
- 4,362 sales reference 4,362 distinct `usuario_uuid` that `tb_usuario` lacks (one sale each,
  all `origem = 'API'`);
- 0 sales have an empty `usuario_uuid`;
- `tb_venda` is append-only (feature 013, T001).

## Decision 10: A third `AUTO CDC` flow, fed by sales whose user silver lacks

- **Decision**:
  - **View** `vw_gold_dim_usuario_tb_venda`, a temporary view over
    `STREAM(workspace.silver.tb_venda) AS v LEFT JOIN workspace.silver.tb_usuario AS u ON u.usuario_uuid = v.usuario_uuid`,
    keeping `WHERE u.usuario_uuid IS NULL AND v.usuario_uuid IS NOT NULL`.
  - **Columns**, in the users flow's shape:
    - `sk_usuario = xxhash64(v.usuario_uuid) & 9223372036854775807`;
    - `usuario_uuid`;
    - `Desconhecido` for `nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`,
      `profissao_usuario`, `empresa_usuario`;
    - `CAST(NULL AS INT) AS idade_usuario`;
    - `v.origem AS origem`;
    - `current_timestamp() AS data_carga`;
    - `TIMESTAMP'1900-01-02' AS data_carga_silver` (Decision 11).
  - **Flow** `gold_dim_usuario_tb_venda_flow AS AUTO CDC INTO workspace.gold.dim_usuario`,
    with `KEYS (usuario_uuid)`, `SEQUENCE BY data_carga_silver`,
    `COLUMNS * EXCEPT (data_carga_silver)` and `STORED AS SCD TYPE 1`. These are the
    users flow's clauses.
- **Rationale**:
  - **Kimball's inferred member**: every user a sale references gets a row with a real key,
    so the fact's lookup always succeeds (FR-013; constitution v3.1.0).
  - **Allowed combination**: the documented pattern allows one snapshot flow plus several
    `AUTO CDC` flows on an SCD type 1 target with the same keys. That is the members
    snapshot, the users flow and this flow.
  - **Stream-static**: `tb_venda` is read as a stream; `tb_usuario` is read without
    `STREAM` and joined `LEFT ... WHERE IS NULL` (the anti-join form most widely supported
    for stream-static joins).
  - **Ordering**: the view reads `tb_usuario` as a batch, so the pipeline loads
    `tb_usuario` first in each update. A user that silver accepts in the same update as its
    sale is found, and no inferred row is written.
  - **Key**: the key expression is identical to the users view (Principle VI, "one
    expression per key"). An inferred user and its later real row share the key.
  - **Attributes**: owner's answer (spec, Clarifications); `origem` comes from the sale.
  - **Only sales**: users referenced only by accesses get none (owner).
- **Alternatives considered**:
  - Inferred rows inside the users view: a stream cannot be unioned with another
    (Principle V), and silver users and sales are different streams.
  - A materialized view of missing users: an `AUTO CDC` source must be a stream (feature
    012, `must be a streaming query`).

## Decision 11: The inferred rows' sequence is fixed at 1900-01-02

- **Decision**: `data_carga_silver = TIMESTAMP'1900-01-02'` for every inferred row.
- **Rationale**:
  - **Real rows win**: a real row is sequenced by silver's load time (2026), so if silver
    later delivers the user, the real row is newer and replaces the inferred one in place,
    with the same key (FR-013).
  - **Safe from the members snapshot**: the snapshot treats absent keys as deleted at its
    version `1900-01-01`. The inferred rows are one day newer, so a full refresh that reruns
    the snapshot does not delete them.
  - **Repeats**: several sales of the same inferred user carry identical values and the same
    sequence. The row stays one row; only `data_carga` may move.
- **Alternatives considered**:
  - The sale's `data_venda` as the sequence: it ties less often, but it ties the dimension
    to sale dates, and a future sale could be dated after the user's silver load time.
  - `1900-01-01`: equal to the snapshot version, so a full refresh could delete the
    inferred rows.

## Decision 12: Renumber the gold files to keep each flow view before its target

- **Decision**: insert `02_vw_gold_dim_usuario_tb_venda.sql` and shift the later files by
  one:

  | Before | After |
  |---|---|
  | `02_dim_usuario.sql` | `03_dim_usuario.sql` |
  | `03_dim_codigos.sql` | `04_dim_codigos.sql` |
  | `04_vw_gold_dim_curso_dados_database.sql` | `05_vw_gold_dim_curso_dados_database.sql` |
  | `05_vw_gold_dim_curso_membros.sql` | `06_vw_gold_dim_curso_membros.sql` |
  | `06_dim_curso.sql` | `07_dim_curso.sql` |
  | `07_fato_venda.sql` | `08_fato_venda.sql` |

  File contents do not change. Every documentation link to these files is updated.
- **Rationale**:
  - Principle V puts each flow view in its own file, numbered just before its target's
    file, with prefixes sequential from `01`.
  - Datasets are identified by name, not by file, so renaming changes no table and no
    streaming state.
  - `import-dir --overwrite` does not delete files, so the six old names are deleted from the
    workspace before the upload. Otherwise each dataset would be defined twice.
- **Alternatives considered**:
  - Numbering the new view `08_`: this breaks "numbered just before the target".
  - Two files sharing `02_`: this breaks "sequential".

## Decision 13: No full refresh; a real update is the test

- **Decision**: add the view and flow, then run an ordinary dry run and update. The new flow
  starts its own checkpoint and reads all of `tb_venda` once. The existing flows and keys
  are untouched.
- **Rationale**:
  - Adding a flow to an existing target needs no refresh.
  - This contract notes that a dry run once accepted what the update rejected, so the real
    update is the proof.
  - If the update rejects the combination (for example, a multi-flow limit), stop and ask the
    owner. A full refresh is not a fix.
- **Expected**: `dim_usuario` grows from 941,236 to 945,598 rows. Every earlier key and
  `data_carga` is unchanged. The anti join of `tb_venda` against `dim_usuario` returns 0 rows.
