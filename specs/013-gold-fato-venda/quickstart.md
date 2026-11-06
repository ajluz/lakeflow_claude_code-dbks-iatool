# Quickstart: Gold Sales Fact

Validates the feature end to end. Expected values come from [spec.md](spec.md) and
[data-model.md](data-model.md), as of 2026-11-05.

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
- `fato_venda` is created as a `STREAMING_TABLE`;
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
  count_if(sk_tempo = -1)   AS tempo_desconhecido,    -- 0
  count_if(sk_codigos = -1) AS codigos_desconhecido,  -- 0
  count_if(sk_curso = -1)   AS curso_desconhecido,    -- 0
  count_if(sk_usuario = -1) AS usuario_desconhecido,  -- 4362
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
  unchanged. The stream reads 0 new rows, and no sale is processed twice.
- Silver, bronze and the four dimensions keep their counts:

  | Dataset | Rows |
  |---|---|
  | `dim_usuario` | 941,236 |
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
