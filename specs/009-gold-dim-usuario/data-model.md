# Data Model: Gold User Dimension

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28, revised 2026-11-04 and 2026-11-05

```text
workspace.silver.tb_usuario   (streaming read)
        │
        ▼
vw_gold_dim_usuario_tb_usuario   (temporary view: computes the key and data_carga)
        │  AUTO CDC, SCD type 1
        ▼
workspace.gold.dim_usuario  ◄── AUTO CDC ONCE FROM SNAPSHOT ── two members
(G1: streaming table, no expectations)
        ▲  AUTO CDC, SCD type 1, sequence 1900-01-02 (2026-11-05)
vw_gold_dim_usuario_tb_venda   (temporary view: users that sales reference and silver lacks)
        ▲
STREAM(workspace.silver.tb_venda)  LEFT JOIN  workspace.silver.tb_usuario (static)  WHERE no match
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

**Inferred users** (FR-013, 2026-11-05): one row per `usuario_uuid` that `tb_venda`
references and `tb_usuario` lacks.

| Column | Value |
|---|---|
| `sk_usuario` | `xxhash64(usuario_uuid) & 9223372036854775807`, the same expression as silver users |
| `usuario_uuid` | the sale's `usuario_uuid` |
| `nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`, `profissao_usuario`, `empresa_usuario` | `'Desconhecido'` |
| `idade_usuario` | null |
| `origem` | the sale's `origem` (`API` today) |
| `data_carga` | `current_timestamp()` when gold writes the row |

Sequence `1900-01-02`: a real silver row (2026) replaces it in place with the same key. It is
recognised by `sk_usuario > 0 AND nome_usuario = 'Desconhecido'`.

| Property | Value | Requirement |
|---|---|---|
| Kind | streaming table, target of three `AUTO CDC` flows (users, inferred users, members snapshot) | FR-001, FR-013 |
| SCD type | 1 (`KEYS (usuario_uuid)`, `SEQUENCE BY` silver's `data_carga`) | FR-004 |
| Surrogate key | `sk_usuario`, deterministic, stable across every update and refresh; negative only for the members | FR-005 |
| Business key | `usuario_uuid` | FR-006 |
| `quality` | `gold` | FR-010 |

## How facts will use it

`fato_venda` resolves `sk_usuario` by joining on `usuario_uuid`. With inferred users every
sale's user has a row: the anti join of `tb_venda` against `dim_usuario` returns 0 rows. The
fact may therefore inner-join (constitution v3.1.0). `-2` remains for facts with no user by
nature. The join stays
the documented method (Principle VII), even though the key could be computed directly.

## Expected rows

```text
941,234 silver users + 4,362 inferred users + 2 members = 945,598   (2026-11-05)
silver: API 741,234 · ARQUIVO 200,000 · inferred: API 4,362 · members 2
```
