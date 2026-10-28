# Data Model: Gold User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

```text
workspace.silver.tb_usuario   (batch read; latest row per usuario_uuid)
        │
        ├──────────── UNION ALL ──── two members (-1 Desconhecido, -2 Não se aplica)
        ▼
workspace.gold.dim_usuario    (G1: materialized view, SCD type 1, 2 FAIL UPDATE expectations)
```

## `workspace.gold.dim_usuario`

Grain: one user. Exactly these 11 columns, in this order.

| Column | Type | Silver rows | Members | Rule |
|---|---|---|---|---|
| `sk_usuario` | BIGINT | `xxhash64(usuario_uuid)` | `-1`, `-2` | `check_sk_usuario`: not null (fail update); unique (verified) |
| `usuario_uuid` | STRING | `usuario_uuid` | `'-1'`, `'-2'` | `check_usuario_uuid`: not null (fail update); unique (verified) |
| `nome_usuario` | STRING | `nome_usuario` | label | — |
| `email_usuario` | STRING | `email_usuario` | label | — |
| `idade_usuario` | INT | `idade_usuario` | null | — |
| `sexo_usuario` | STRING | `sexo_usuario` | label | — |
| `estado_usuario` | STRING | `estado_usuario` | label | — |
| `profissao_usuario` | STRING | `profissao_usuario` | label | — |
| `empresa_usuario` | STRING | `empresa_usuario` (null for `API`) | label | — |
| `origem` | STRING | `origem` (`API`, `ARQUIVO`) | label | — |
| `data_carga` | TIMESTAMP | `current_timestamp()` | `current_timestamp()` | — |

Label: `'Desconhecido'` for `-1`, `'Não se aplica'` for `-2`.

| Property | Value | Requirement |
|---|---|---|
| Kind | materialized view, batch read of silver | FR-001 |
| SCD type | 1 (`QUALIFY row_number() ... ORDER BY data_carga DESC = 1`) | FR-004 |
| Surrogate key | `sk_usuario`, deterministic, stable across every update and refresh | FR-005 |
| Business key | `usuario_uuid` | FR-006 |
| `quality` | `gold` | FR-010 |

## How facts will use it

`fato_venda` (a later feature) resolves `sk_usuario` by joining on `usuario_uuid`; when
there is no match, it uses `-1`; when the fact has no user by nature, `-2`. Because
`sk_usuario = xxhash64(usuario_uuid)`, the fact could also compute the key directly; the
join stays the documented method (Principle VII).

## Expected rows (2026-10-28)

```text
941,234 silver users + 2 members = 941,236
API 741,234 · ARQUIVO 200,000 · members 2
```
