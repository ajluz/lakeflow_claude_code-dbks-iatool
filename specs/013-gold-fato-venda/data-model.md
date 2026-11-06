# Data Model: Gold Sales Fact

## Lineage

```text
STREAM(silver.tb_venda) ──┐   (incremental: each sale processed once)
silver.tb_acesso ─────────┤   (static; location of site sales only, LEFT JOIN)
                  ▼
            vendas (CTE: one row per sale, the 4 codes, measures, date, user, course)
                  │  LEFT JOIN gold.dim_tempo    ON data = CAST(data_venda AS DATE)
                  │  LEFT JOIN gold.dim_codigos  ON the 4 codes
                  │  LEFT JOIN versoes_curso     ON curso_uuid + version in effect / first version
                  │  LEFT JOIN gold.dim_usuario  ON usuario_uuid
                  ▼
workspace.gold.fato_venda  (streaming table; dimensions read static; every key coalesce(…, -1))
```

## `workspace.gold.fato_venda` (streaming table)

**Grain**: one row per sale of `silver.tb_venda`. `quality` = `gold`. No expectations.

| # | Column | Type | Resolution | Kind |
|---|---|---|---|---|
| 1 | `sk_tempo` | BIGINT | `dim_tempo` row whose `data` = the sale's day; else `-1` | dimension key |
| 2 | `sk_codigos` | BIGINT | `dim_codigos` row matching all four codes (below); else `-1` | dimension key |
| 3 | `sk_curso` | BIGINT | `dim_curso` version in effect at `data_venda`, or the course's first version if the sale is older; else `-1` | dimension key |
| 4 | `sk_usuario` | BIGINT | `dim_usuario` row with the sale's `usuario_uuid`; else `-1` | dimension key |
| 5 | `valor_desconto` | DECIMAL(9,2) | `tb_venda.valor_desconto` | measure, additive |
| 6 | `valor_pago` | DECIMAL(9,2) | `tb_venda.valor_pago` | measure, additive |

### The four sale codes (as in `dim_codigos`)

| Code | Value |
|---|---|
| `origem_usuario` | `tb_venda.origem` (`API`, `ARQUIVO`) |
| `local_acesso` | `ARQUIVO` → `Não se aplica`; `API` → `tb_acesso.local_acesso` by `acesso_uuid`, `Desconhecido` when there is no access row |
| `forma_pagamento` | `tb_venda.forma_pagamento`, `Desconhecido` when empty |
| `percentual_desconto` | `tb_venda.percentual_desconto`, `Não se aplica` when empty |

### Course version rule (FR-005)

For a sale at `data_venda` and its course's versions, members excluded:
1. **In effect**: `__START_AT ≤ data_venda` and (`__END_AT` is empty or `data_venda < __END_AT`).
2. **Otherwise, if the sale is older than the first version**: the version with the earliest
   `__START_AT`.
3. **Otherwise**: `-1`, for a sale in a gap after a deletion or after the last version
   closed.

The three cases are mutually exclusive, so a sale gets at most one version. The lookup is
never limited to `__END_AT IS NULL`.

### Invariants (checked by query)

- Row count = `silver.tb_venda` row count.
- `sum(valor_pago)` and `sum(valor_desconto)` = silver's.
- No key is empty. Every key exists in its dimension.
- File sales' codes have `local_acesso = 'Não se aplica'`; site sales' codes never do.

## Expected values (2026-11-05)

| Measure | Value |
|---|---|
| Rows | 420,472 (API 220,472, ARQUIVO 200,000) |
| `sk_tempo = -1` | 0 |
| `sk_usuario = -1` | 4,362 |
| `sk_codigos = -1` | 0 |
| Site sales with location `Desconhecido` | 2,174 |
| `sk_curso = -1` | 0 |
| Distinct `sk_curso` | 3, each course's only version |
| Distinct `sk_codigos` | 22 (as counted in feature 011) |

Keys are resolved once, when a sale is processed (research, Decision 9). At the live
demo, after `update row` and `delete row`, every existing sale keeps its `sk_curso`: it was
already written, and FR-005 puts it on the first version anyway.
