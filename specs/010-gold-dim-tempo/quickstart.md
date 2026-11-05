# Quickstart: Gold Calendar Dimension

Validates the feature end to end. Expected values come from [spec.md](spec.md) and
[data-model.md](data-model.md).

## Prerequisites

- Step 01 has run (`workspace.gold` exists).
- A CLI profile chosen by you, here `databricks-free`, logged in.

## 1. First run

```bash
databricks experimental aitools tools query explorations/setup/04_dim_tempo.sql --profile databricks-free
```

Expected summary row: `linhas` 3654, `dias` 3652, `membros` 2, `primeiro_dia` 2021-01-01,
`ultimo_dia` 2030-12-31, `dias_repetidos` 0.

## 2. Record the keys

```sql
SELECT count(*) AS linhas,
       sum(hash(sk_tempo, data, data_carga)) AS checksum
FROM workspace.gold.dim_tempo;
```

## 3. Second run, then compare

Run step 1 again, then step 2. Expected: the same summary row, and `linhas` and
`checksum` identical to step 2 (SC-003).

## 4. Content checks

```sql
SELECT
  count(*) - count(DISTINCT sk_tempo)                            AS sk_repetidas,     -- 0
  count_if(sk_tempo IS NULL)                                     AS sk_vazias,        -- 0
  count_if(data IS NOT NULL) - count(DISTINCT data)              AS datas_repetidas,  -- 0
  count_if(sk_tempo < 0) AS chaves_negativas,                                         -- 2
  count_if(data IS NULL AND sk_tempo IN (-1, -2))                AS membros_ok,       -- 2
  count_if(fl_ultimo_dia_mes)                                    AS fins_de_mes,      -- 120
  count_if(fl_dia_semana <> (dia_semana_int BETWEEN 2 AND 6))    AS flag_errada,      -- 0
  count_if(data IS NOT NULL AND dia_semana_int = 1 AND dia_semana <> 'domingo') AS nome_errado, -- 0
  max(dia_ano)                                                   AS max_dia_ano       -- 366
FROM workspace.gold.dim_tempo;
```

Spot checks:

```sql
SELECT data, mes, dia_semana, fl_ultimo_dia_mes, semana_ano, bimestre, trimestre, semestre
FROM workspace.gold.dim_tempo
WHERE data IN (DATE'2021-01-01', DATE'2024-02-29', DATE'2024-12-30', DATE'2030-12-31');
```

Expected: 2021-01-01 `janeiro`, `sexta-feira`, week 53, bimester 1, quarter 1, semester 1;
2024-02-29 `fevereiro`, `quinta-feira`, `fl_ultimo_dia_mes` true; 2024-12-30
`segunda-feira`, week 1; 2030-12-31 `dezembro`, `terça-feira`, week 1, bimester 6,
quarter 4, semester 2.

## 5. Coverage of silver dates (SC-006)

```sql
SELECT count(*) AS vendas_sem_dia   -- 0
FROM workspace.silver.tb_venda AS v
LEFT JOIN workspace.gold.dim_tempo AS t ON t.data = CAST(v.data_venda AS DATE)
WHERE v.data_venda IS NOT NULL AND t.sk_tempo IS NULL;
```

## 6. The old cell is gone

`grep -n dim_tempo explorations/functions.py` returns nothing.

Stop the warehouse afterwards (`databricks warehouses stop <id> --no-wait --profile databricks-free`).
