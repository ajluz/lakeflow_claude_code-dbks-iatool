# Quickstart: Gold Sales Fact

Validates the feature end to end. Expected values come from [spec.md](spec.md) and
[data-model.md](data-model.md), as of 2026-11-06 (inner joins to the dimensions).

## 0. Coverage before the change (Principle V, SC-006)

Before the inner joins are uploaded, each anti join of the sales against a dimension must
return 0. Use the CTE `vendas` of `07_fato_venda.sql` without `STREAM`:

```sql
-- with vendas as in the fact, and versoes_curso with proximo_inicio and primeiro_inicio
SELECT count(*) FROM vendas s LEFT ANTI JOIN workspace.gold.dim_tempo t ON t.data = CAST(s.data_venda AS DATE);   -- 0
SELECT count(*) FROM vendas s LEFT ANTI JOIN workspace.gold.dim_codigos c
  ON c.origem_usuario = s.origem_usuario AND c.local_acesso = s.local_acesso
 AND c.forma_pagamento = s.forma_pagamento AND c.percentual_desconto = s.percentual_desconto;                       -- 0
SELECT count(*) FROM vendas s LEFT ANTI JOIN versoes_curso k ON k.curso_uuid = s.curso_uuid
 AND ((k.__START_AT <= s.data_venda AND (k.proximo_inicio IS NULL OR s.data_venda < k.proximo_inicio))
   OR (s.data_venda < k.primeiro_inicio AND k.__START_AT = k.primeiro_inicio));                                     -- 0
SELECT count(*) FROM vendas s LEFT ANTI JOIN workspace.gold.dim_usuario u ON u.usuario_uuid = s.usuario_uuid;      -- 0
```

The same new query, run as a batch, returns 420,472 rows with checksum 581165462078, equal to
the stored fact (research, Decision 10). If any count differs, stop: the change would
drop or move sales.

## Prerequisites

- Profile `databricks-free`, logged in.
- Pipeline `8d51ac7a-02be-4ce2-8afd-f4f263e448dd` idle.
- Warehouse `f796ffb64302b6ba`.
- `### fato_venda` in `doc/pipeline-reference.md` already states the grain (Principle VII).
- `src/pipeline/03_gold/07_fato_venda.sql` uploaded and identical in the workspace.
- About 4 minutes between updates.

## 1. Dry run, then update

```bash
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --validate-only --profile databricks-free
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free
```

Expected:
- both runs end `COMPLETED`;
- `fato_venda` stays a `STREAMING_TABLE`, updated in place;
- no other dataset fails;
- this is not a full refresh.

## 2. Reconciliation (SC-001, SC-002)

```sql
SELECT
  (SELECT count(*) FROM workspace.gold.fato_venda)                     AS linhas_fato,      -- 420472
  (SELECT count(*) FROM workspace.silver.tb_venda)                     AS linhas_silver,    -- 420472
  (SELECT sum(valor_pago) FROM workspace.gold.fato_venda)
    - (SELECT sum(valor_pago) FROM workspace.silver.tb_venda)          AS dif_pago,         -- 0.00
  (SELECT sum(valor_desconto) FROM workspace.gold.fato_venda)
    - (SELECT sum(valor_desconto) FROM workspace.silver.tb_venda)      AS dif_desconto;     -- 0.00
```

## 3. Keys (SC-003, SC-005, SC-006)

```sql
SELECT
  count_if(sk_tempo IS NULL OR sk_codigos IS NULL OR sk_curso IS NULL OR sk_usuario IS NULL) AS vazias, -- 0
  count_if(sk_tempo < 0)    AS tempo_membro,          -- 0
  count_if(sk_codigos < 0)  AS codigos_membro,        -- 0
  count_if(sk_curso < 0)    AS curso_membro,          -- 0
  count_if(sk_usuario < 0)  AS usuario_membro,        -- 0
  count(DISTINCT sk_curso)   AS cursos,                -- 3
  count(DISTINCT sk_codigos) AS combinacoes            -- 22
FROM workspace.gold.fato_venda;

-- every key exists in its dimension, and the star join keeps every row
SELECT count(*) AS linhas_estrela          -- 420472
FROM workspace.gold.fato_venda f
JOIN workspace.gold.dim_tempo   t ON t.sk_tempo   = f.sk_tempo
JOIN workspace.gold.dim_codigos c ON c.sk_codigos = f.sk_codigos
JOIN workspace.gold.dim_curso   k ON k.sk_curso   = f.sk_curso
JOIN workspace.gold.dim_usuario u ON u.sk_usuario = f.sk_usuario;
```

## 4. File sales and access locations (SC-004, SC-005)

```sql
SELECT c.origem_usuario, c.local_acesso, count(*) AS vendas
FROM workspace.gold.fato_venda f
JOIN workspace.gold.dim_codigos c ON c.sk_codigos = f.sk_codigos
GROUP BY ALL ORDER BY ALL;
```

Expected:
- `ARQUIVO` appears only with `Não se aplica` (200,000 sales);
- `API` never appears with `Não se aplica`;
- `API` with `Desconhecido` has 2,174 sales.

## 5. Course versions (FR-005)

```sql
SELECT k.curso_uuid, k.sk_curso, k.__START_AT, k.__END_AT, count(*) AS vendas
FROM workspace.gold.fato_venda f
JOIN workspace.gold.dim_curso k ON k.sk_curso = f.sk_curso
GROUP BY ALL ORDER BY ALL;
```

Expected:
- 3 rows, one per course, each the course's only (and first) version;
- the sales add up to 420,472;
- no row has `sk_curso` < 0.

## 6. Stability and nothing else changed

- A second ordinary update with no new sales leaves the row count and
  `sum(hash(sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago))`
  unchanged (420,472 and 581165462078 on 2026-11-06). The stream reads 0 new rows, and no
  sale is processed twice. The update that applies the inner joins leaves them unchanged
  too.
- Silver, bronze and the four dimensions keep their counts:

  | Dataset | Rows |
  |---|---|
  | `dim_usuario` | 956,251 |
  | `dim_codigos` | 62 |
  | `dim_curso` | 5 |
  | `dim_tempo` | 3,654 |
  | `tb_venda` | 420,472 |
  | `tb_acesso` | 2,516,192 |

Stop the warehouse afterwards with `--no-wait`.

## At the live demo (owner)

After `update row` / `delete row` and an update, step 5 still shows the same three
`sk_curso` with the same sale counts. Past sales were already written and are not
reprocessed. FR-005 keeps them on the first version anyway.
