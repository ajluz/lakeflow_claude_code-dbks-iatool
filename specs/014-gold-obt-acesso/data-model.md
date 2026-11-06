# Data Model: Gold Access One-Big-Table

## Lineage

```text
silver.tb_venda ── vendas_por_acesso (CTE: site sales counted per acesso_uuid)
                          │ LEFT JOIN ON acesso_uuid
silver.tb_acesso ─────────┤
                          ▼
                 acessos (CTE: GROUP BY local_acesso, endereco_ip_acesso, data; 3 counts)
                          │ LEFT JOIN gold.dim_tempo ON data
                          ▼
workspace.gold.obt_acesso  (materialized view, recomputed on every update)
```

## `workspace.gold.obt_acesso` (materialized view)

**Grain**: one row per combination of `local_acesso`, `endereco_ip_acesso` and `data`.
`quality` = `gold`. No expectations.

| # | Column | Type | Source |
|---|---|---|---|
| 1 | `local_acesso` | STRING | `tb_acesso.local_acesso` (`Computador`, `Mobile`, `unknown`) |
| 2 | `endereco_ip_acesso` | STRING | `tb_acesso.endereco_ip_acesso` |
| 3 | `data` | DATE | `CAST(tb_acesso.timestamp_acesso AS DATE)` |
| 4 | `ano` | INT | `dim_tempo` |
| 5 | `mes` | STRING | `dim_tempo` (Portuguese month name) |
| 6 | `mes_ano` | INT | `dim_tempo` (month number) |
| 7 | `dia_mes` | INT | `dim_tempo` |
| 8 | `dia_semana` | STRING | `dim_tempo` (Portuguese day name) |
| 9 | `dia_semana_int` | INT | `dim_tempo` (1 = Sunday … 7 = Saturday) |
| 10 | `fl_dia_semana` | BOOLEAN | `dim_tempo` (true Monday–Friday) |
| 11 | `dia_ano` | INT | `dim_tempo` |
| 12 | `fl_ultimo_dia_mes` | BOOLEAN | `dim_tempo` |
| 13 | `semana_ano` | INT | `dim_tempo` (ISO week) |
| 14 | `semestre` | INT | `dim_tempo` |
| 15 | `trimestre` | INT | `dim_tempo` |
| 16 | `bimestre` | INT | `dim_tempo` |
| 17 | `qtde_acesso` | BIGINT | accesses of the combination; always ≥ 1 |
| 18 | `qtde_usuario` | BIGINT | accesses of the combination that carry a user |
| 19 | `qtde_vendidos` | BIGINT | site sales linked to the combination's accesses; 0 when none |

All three counts are additive across every column.

## Invariants (checked by query)

- `sum(qtde_acesso)` = rows of `silver.tb_acesso`.
- `sum(qtde_usuario)` = rows of `silver.tb_acesso` with a `usuario_uuid`.
- `sum(qtde_vendidos)` = site sales of `silver.tb_venda` whose `acesso_uuid` is in
  `silver.tb_acesso`.
- No two rows share (`local_acesso`, `endereco_ip_acesso`, `data`); every `qtde_acesso` ≥ 1.
- The 13 calendar columns equal `dim_tempo`'s for `data`; 0 rows without them.
- The same sums per `local_acesso` and per `data` equal the sources'.

## Expected values (2026-11-06)

See [research.md](research.md), Decision 6: 2,516,058 rows; sums 2,516,192 / 748,571 /
218,298; per location and per day as listed there.
