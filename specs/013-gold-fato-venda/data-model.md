# Data Model: Gold Sales Fact

## Lineage

```text
STREAM(silver.tb_venda) ──┐   (incremental: each sale processed once)
silver.tb_acesso ─────────┤   (static; location of site sales only, LEFT JOIN from the sales)
                  ▼
            vendas (CTE: one row per sale, the 4 codes, measures, date, user, course)
                  │  JOIN gold.dim_tempo    ON data = CAST(data_venda AS DATE)
                  │  JOIN gold.dim_codigos  ON the 4 codes
                  │  JOIN versoes_curso     ON curso_uuid + course rule (FR-005)
                  │  JOIN gold.dim_usuario  ON usuario_uuid
                  ▼
workspace.gold.fato_venda  (streaming table; dimensions read static; inner joins with proven coverage)
```

## `workspace.gold.fato_venda` (streaming table)

**Grain**: one row per sale of `silver.tb_venda`. `quality` = `gold`. No expectations.

| # | Column | Type | Resolution | Kind |
|---|---|---|---|---|
| 1 | `sk_tempo` | BIGINT | `dim_tempo` row whose `data` = the sale's day | dimension key |
| 2 | `sk_codigos` | BIGINT | `dim_codigos` row matching all four codes (below) | dimension key |
| 3 | `sk_curso` | BIGINT | `dim_curso` version picked by the course rule (below) | dimension key |
| 4 | `sk_usuario` | BIGINT | `dim_usuario` row with the sale's `usuario_uuid` | dimension key |
| 5 | `valor_desconto` | DECIMAL(9,2) | `tb_venda.valor_desconto` | measure, additive |
| 6 | `valor_pago` | DECIMAL(9,2) | `tb_venda.valor_pago` | measure, additive |

Each dimension lookup is an inner join. Its coverage is guaranteed and verified by an anti
join that returns 0 (research, Decision 2). No key uses `-1` or `-2`.

### The four sale codes (as in `dim_codigos`)

| Code | Value |
|---|---|
| `origem_usuario` | `tb_venda.origem` (`API`, `ARQUIVO`) |
| `local_acesso` | `ARQUIVO` → `Não se aplica`, never looked up; `API` → `tb_acesso.local_acesso` by `acesso_uuid`, `Desconhecido` when there is no access row |
| `forma_pagamento` | `tb_venda.forma_pagamento`, `Desconhecido` when empty |
| `percentual_desconto` | `tb_venda.percentual_desconto`, `Não se aplica` when empty |

The access lookup is a left join from the sales, so only accesses that ended in a purchase
are read (FR-009).

### Course rule (FR-005)

For a sale at `data_venda` and its course's versions, members excluded, each version is
valid from its `__START_AT` until the next version's `__START_AT` (open for the latest):
1. **In effect**: the version whose window contains `data_venda`. After a deletion, or in a
   gap before a re-insertion, this is the last version that started before the sale.
2. **Older than every version**: the version with the earliest `__START_AT`.

The two cases are mutually exclusive and cover every date, so a sale whose course has any
version gets exactly one. The lookup is never limited to `__END_AT IS NULL`.

### Invariants (checked by query)

- Row count = `silver.tb_venda` row count, after every load.
- `sum(valor_pago)` and `sum(valor_desconto)` = silver's.
- No key is empty or below 0. Every key exists in its dimension.
- Anti join of `silver.tb_venda` against each dimension = 0.
- File sales' codes have `local_acesso = 'Não se aplica'`; site sales' codes never do.

## Expected values (2026-11-06)

| Measure | Value |
|---|---|
| Rows | 420,472 (API 220,472, ARQUIVO 200,000) |
| Keys below 0 | 0 in each of the four keys |
| Site sales with location `Desconhecido` | 2,174 |
| Distinct `sk_curso` | 3, each course's only version |
| Distinct `sk_codigos` | 22 |
| Checksum `sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))` | 581165462078, unchanged by this revision |

Keys are resolved once, when a sale is processed (research, Decision 9). At the live
demo, after `update row` and `delete row`, every existing sale keeps its `sk_curso`: it was
already written, and FR-005 puts it on the first version anyway.
