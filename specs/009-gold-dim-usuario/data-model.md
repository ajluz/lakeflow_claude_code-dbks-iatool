# Data Model: Gold User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28, revised 2026-11-04

```text
workspace.silver.tb_usuario   (streaming read)
        │
        ▼
vw_gold_dim_usuario_tb_usuario   (temporary view: computes the key and data_carga)
        │  AUTO CDC, SCD type 1
        ▼
workspace.gold.dim_usuario  ◄── AUTO CDC ONCE FROM SNAPSHOT ── two members
(G1: streaming table, no expectations)
```

## `workspace.gold.dim_usuario`

Grain: one user. Exactly these 11 columns, in this order.

| Column | Type | Silver rows | Members | Rule |
|---|---|---|---|---|
| `sk_usuario` | BIGINT | `xxhash64(usuario_uuid) & 9223372036854775807` | `-1`, `-2` | not null and unique (verified by query) |
| `usuario_uuid` | STRING | `usuario_uuid` | `'-1'`, `'-2'` | not null and unique (verified by query) |
| `nome_usuario` | STRING | `nome_usuario` | label | — |
| `email_usuario` | STRING | `email_usuario` | label | — |
| `idade_usuario` | INT | `idade_usuario` | null | — |
| `sexo_usuario` | STRING | `sexo_usuario` | label | — |
| `estado_usuario` | STRING | `estado_usuario` | label | — |
| `profissao_usuario` | STRING | `profissao_usuario` | label | — |
| `empresa_usuario` | STRING | `empresa_usuario` (null for `API`) | label | — |
| `origem` | STRING | `origem` (`API`, `ARQUIVO`) | label | — |
| `data_carga` | TIMESTAMP | `current_timestamp()` when gold writes the row | `current_timestamp()` when gold writes the row | — |

Label: `'Desconhecido'` for `-1`, `'Não se aplica'` for `-2`.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, target of two `AUTO CDC` flows | FR-001 |
| SCD type | 1 (`KEYS (usuario_uuid)`, `SEQUENCE BY` silver's `data_carga`) | FR-004 |
| Surrogate key | `sk_usuario`, deterministic, stable across every update and refresh; negative only for the members | FR-005 |
| Business key | `usuario_uuid` | FR-006 |
| `quality` | `gold` | FR-010 |

## How facts will use it

`fato_venda` (a later feature) resolves `sk_usuario` by joining on `usuario_uuid`; when
there is no match, it uses `-1`; when the fact has no user by nature, `-2`. The join stays
the documented method (Principle VII), even though the key could be computed directly.

## Expected rows

```text
941,234 silver users + 2 members = 941,236
API 741,234 · ARQUIVO 200,000 · members 2
```
