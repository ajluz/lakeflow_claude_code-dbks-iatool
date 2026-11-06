# Quickstart: Gold Access One-Big-Table

Validates the feature end to end. Expected values come from [spec.md](spec.md) and
[research.md](research.md), Decision 6, as of 2026-11-06.

## Prerequisites

- Profile `databricks-free`, logged in.
- Pipeline `8d51ac7a-02be-4ce2-8afd-f4f263e448dd` idle.
- Warehouse `f796ffb64302b6ba`.
- `### obt_acesso` in `doc/pipeline-reference.md` already states the grain (FR-013).
- `src/pipeline/03_gold/08_obt_acesso.sql` uploaded and identical in the workspace.
- About 4 minutes between updates.

## 1. Dry run, then update

```bash
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --validate-only --profile databricks-free
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free
```

Expected:
- both runs end `COMPLETED`;
- `obt_acesso` is created as a `MATERIALIZED_VIEW`;
- no other dataset fails;
- this is not a full refresh.

## 2. Totals against the sources (SC-001, SC-002, SC-003)

```sql
SELECT
  (SELECT sum(qtde_acesso) FROM workspace.gold.obt_acesso)
    - (SELECT count(*) FROM workspace.silver.tb_acesso)                          AS dif_acesso,   -- 0
  (SELECT sum(qtde_usuario) FROM workspace.gold.obt_acesso)
    - (SELECT count_if(usuario_uuid IS NOT NULL) FROM workspace.silver.tb_acesso) AS dif_usuario,  -- 0
  (SELECT sum(qtde_vendidos) FROM workspace.gold.obt_acesso)
    - (SELECT count(*) FROM workspace.silver.tb_venda v
       LEFT SEMI JOIN workspace.silver.tb_acesso a ON a.acesso_uuid = v.acesso_uuid
       WHERE v.origem = 'API')                                                   AS dif_vendidos, -- 0
  (SELECT count(*) FROM workspace.gold.obt_acesso)                               AS linhas;       -- 2516058
```

## 3. Grain, calendar and columns (SC-004, SC-006, SC-007)

```sql
SELECT
  count(*) - count(DISTINCT local_acesso, endereco_ip_acesso, data) AS combinacoes_repetidas, -- 0
  count_if(qtde_acesso < 1)  AS sem_acesso,      -- 0
  count_if(data IS NULL)     AS sem_data,        -- 0
  max(qtde_acesso)           AS maior_qtde       -- 2
FROM workspace.gold.obt_acesso;

-- calendar columns equal dim_tempo's
SELECT count(*) AS divergentes   -- 0
FROM workspace.gold.obt_acesso o
LEFT JOIN workspace.gold.dim_tempo t ON t.data = o.data
WHERE NOT (o.ano <=> t.ano AND o.mes <=> t.mes AND o.mes_ano <=> t.mes_ano AND o.dia_mes <=> t.dia_mes
       AND o.dia_semana <=> t.dia_semana AND o.dia_semana_int <=> t.dia_semana_int
       AND o.fl_dia_semana <=> t.fl_dia_semana AND o.dia_ano <=> t.dia_ano
       AND o.fl_ultimo_dia_mes <=> t.fl_ultimo_dia_mes AND o.semana_ano <=> t.semana_ano
       AND o.semestre <=> t.semestre AND o.trimestre <=> t.trimestre AND o.bimestre <=> t.bimestre)
   OR t.data IS NULL;

-- the 19 columns, in order
SELECT concat_ws(', ', collect_list(concat(column_name, ' ', full_data_type))) FROM (
  SELECT column_name, full_data_type FROM workspace.information_schema.columns
  WHERE table_schema = 'gold' AND table_name = 'obt_acesso' ORDER BY ordinal_position);
```

Also: `SHOW TBLPROPERTIES workspace.gold.obt_acesso ('quality')` is `gold`.

## 4. Per location and per day (SC-005)

```sql
SELECT local_acesso, sum(qtde_acesso), sum(qtde_usuario), sum(qtde_vendidos)
FROM workspace.gold.obt_acesso GROUP BY ALL ORDER BY ALL;
SELECT data, sum(qtde_acesso), sum(qtde_usuario), sum(qtde_vendidos)
FROM workspace.gold.obt_acesso GROUP BY ALL ORDER BY ALL;
```

Expected: the values of research.md, Decision 6:
- `Computador` 1,136,377 / 340,520 / 102,148; `Mobile` 1,262,684 / 379,439 / 113,846;
  `unknown` 117,131 / 28,612 / 2,304;
- 2024-06-01 881,045 / 262,742 / 77,232; 2024-06-02 880,259 / 260,646 / 75,597;
  2024-06-03 754,888 / 225,183 / 65,469.

## 5. Stability and nothing else changed

- A second ordinary update with no new data leaves the row count and the three sums
  unchanged.
- The other datasets keep their counts: `tb_acesso` 2,516,192, `tb_venda` 420,472,
  `fato_venda` 420,472 (checksum 581165462078), `dim_usuario` 956,251, `dim_codigos` 62,
  `dim_curso` 5, `dim_tempo` 3,654.

Stop the warehouse afterwards with `--no-wait`.
