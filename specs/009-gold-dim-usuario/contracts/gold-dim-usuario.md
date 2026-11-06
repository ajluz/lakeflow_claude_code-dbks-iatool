# Contract: The Gold User Dimension

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-28, revised 2026-11-04 and 2026-11-05

`fato_venda` and `obt_acesso` will rely on `dim_usuario`'s keys and members.

## Files

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/03_gold/01_vw_gold_dim_usuario_tb_usuario.sql` | `vw_gold_dim_usuario_tb_usuario` (temporary view) | `workspace.silver.tb_usuario`, streaming |
| `src/pipeline/03_gold/02_dim_usuario.sql` | `workspace.gold.dim_usuario` (streaming table) | the view, plus two literal member rows |

The two files as built are the binding statements. If a change is rejected, stop and ask the
owner. Validate a change to the view with a real update: a dry run accepted a `UNION` that
the update rejected. The members flow's `WITH VERSION` is binding: without it, the users
could be treated as deleted.

## What the definition must not contain

| Forbidden | Why |
|---|---|
| `GENERATED ... AS IDENTITY`, `row_number()` or `monotonically_increasing_id()` as the surrogate key | not supported on `AUTO CDC` targets; Principle VII (keys that can be reassigned) |
| `CREATE OR REFRESH MATERIALIZED VIEW` | owner's direction, 2026-11-04 |
| `CONSTRAINT ... EXPECT` | the spec requests none (FR-008; constitution v2.0.0) |
| `UNION` of the silver stream with literal rows | Spark rejects it when the update runs |
| a read of `workspace.bronze.*` or of another dimension | Principles I and VII |
| `ON VIOLATION DROP ROW`; silver's quality rules | spec: the dimension does not re-apply silver's rules |
| `dt_carga` | the constitution's name is `data_carga` |
| `PARTITIONED BY`, `CLUSTER BY`, `ai_*` | Principle V; v1.10.0 |
| columns beyond the 11 | spec FR-002 |

## What consumers may rely on

- One row per `usuario_uuid`; `sk_usuario` and `usuario_uuid` unique and never null.
- **No coverage guarantee**: users that silver rejected (4,362 referenced by sales on
  2026-11-06) have no row. A fact MUST look them up with a left join and `-1`, not an inner join
  (inferred users were tried on 2026-11-05 and undone on 2026-11-06).
- `sk_usuario` never changes for a given user, whatever is refreshed.
- `sk_usuario = -1` is "unknown", `-2` is "not applicable"; both always exist. No other key
  is negative.
- Attributes equal silver's latest row for the user.
