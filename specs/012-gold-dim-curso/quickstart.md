# Quickstart: Gold Course Dimension (SCD Type 2)

Validates the feature end to end. Expected values come from [spec.md](spec.md) and
[data-model.md](data-model.md), as of 2026-11-05.

## Prerequisites

- Profile `databricks-free`, logged in.
- Pipeline `8d51ac7a-02be-4ce2-8afd-f4f263e448dd` idle.
- Warehouse `f796ffb64302b6ba`.
- In the workspace, `03_gold` holds `04_vw_gold_dim_curso_dados_database.sql`,
  `05_vw_gold_dim_curso_membros.sql` and `06_dim_curso.sql`, each identical to the
  repository. The old `05_dim_curso.sql` is deleted.
- About 4 minutes between pipeline updates.
- Do **not** run the generator's `update row` or `delete row`.

## 1. Dry run, then update

```bash
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --validate-only --profile databricks-free
databricks pipelines start-update 8d51ac7a-02be-4ce2-8afd-f4f263e448dd --profile databricks-free
```

Expected:
- both runs end `COMPLETED`;
- `dim_curso` is still a `STREAMING_TABLE`, now with the flows `gold_dim_curso_flow` and
  `gold_dim_curso_membros_flow`;
- no other dataset fails;
- this is not a full refresh.

## 2. Content (SC-001, SC-002, SC-005, SC-007)

```sql
SELECT
  count(*)                                                    AS linhas,        -- 5
  count(DISTINCT sk_curso)                                    AS chaves,        -- 5
  count_if(sk_curso IS NULL OR curso_uuid IS NULL)            AS vazios,        -- 0
  count_if(sk_curso < 0)                                      AS membros,       -- 2
  count_if(sk_curso = 0)                                      AS chave_zero,    -- 0
  count_if(sk_curso > 0 AND __END_AT IS NULL)                 AS cursos_atuais, -- 3
  count_if(__END_AT IS NOT NULL)                              AS fechadas,      -- 0
  count_if(data_carga IS NULL)                                AS sem_carga      -- 0
FROM workspace.gold.dim_curso;

SELECT curso_uuid, count(*) AS linhas, count_if(__END_AT IS NULL) AS abertas
FROM workspace.gold.dim_curso GROUP BY curso_uuid HAVING abertas > 1 OR (curso_uuid IN ('-1','-2') AND linhas <> 1);
-- 0 rows

SELECT * FROM workspace.gold.dim_curso WHERE sk_curso < 0 ORDER BY sk_curso DESC;
-- -1 '-1' Desconhecido ×2, -2 '-2' Não se aplica ×2; valor_curso empty;
-- __START_AT 1900-01-01, __END_AT empty

DESCRIBE workspace.gold.dim_curso;
-- exactly: sk_curso bigint, curso_uuid, nome_curso, nivel_curso, valor_curso decimal(9,2),
-- data_carga, __START_AT, __END_AT
```

## 3. Course keys unchanged, current versions equal silver (SC-003)

```sql
SELECT count(*) AS linhas,                                                     -- 3
       sum(hash(sk_curso, curso_uuid, nome_curso, nivel_curso, valor_curso,
                __START_AT, __END_AT)) AS chk_sem_carga                        -- -380130840
FROM workspace.gold.dim_curso WHERE sk_curso > 0;
```

`-380130840` was recorded after update `3f2c2771`, so adding the members left every course
version untouched.

```sql
WITH gold AS (
  SELECT curso_uuid, nome_curso, nivel_curso, valor_curso
  FROM workspace.gold.dim_curso WHERE __END_AT IS NULL AND sk_curso > 0
), silver AS (
  SELECT curso_uuid, nome_curso, nivel_curso, valor_curso FROM workspace.silver.tb_curso
)
SELECT (SELECT count(*) FROM (SELECT * FROM gold EXCEPT ALL SELECT * FROM silver)) AS so_gold,   -- 0
       (SELECT count(*) FROM (SELECT * FROM silver EXCEPT ALL SELECT * FROM gold)) AS so_silver; -- 0
```

## 4. Rows and keys survive another update (SC-004)

```sql
SELECT count(*) AS linhas,
       sum(hash(sk_curso, curso_uuid, nome_curso, nivel_curso, valor_curso,
                data_carga, __START_AT, __END_AT)) AS checksum
FROM workspace.gold.dim_curso;
```

Wait about 4 minutes, run a second ordinary update, and repeat.

Expected:
- `linhas` 5 and an identical `checksum`, `data_carga` included;
- no new change was read, and the members flow is `ONCE`, so it stays idle.

## 5. Nothing else changed

`bronze.dados_database` 3, `silver.tb_curso` 3, `dim_usuario` 941,236, `dim_codigos` 62,
`tb_venda` 420,472 and `tb_acesso` 2,516,192.

Stop the warehouse afterwards with `--no-wait`.

## At the live demo (SC-006, owner)

After `generate_database_data(type_of_data='update row')` and an update:
- the updated course has 2 rows: `247.00` closed and `147.00` open, with different keys;
- the old key is unchanged;
- the members are still 1 row each, open.

After `delete row` and an update:
- the course has no open row and still has 2 rows;
- the other courses and the members are unchanged.
