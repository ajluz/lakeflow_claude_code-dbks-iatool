# Quickstart: Validate the Course Table

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-28

Shapes are in [data-model.md](data-model.md) and
[contracts/silver-tb-curso.md](contracts/silver-tb-curso.md). Every CLI command takes
`--profile databricks-free`. `<pipeline_id>` is `8d51ac7a-02be-4ce2-8afd-f4f263e448dd`.

## Prerequisites

- **The constitution amendment** of the plan's Complexity Tracking is approved and
  committed.
- `12_vw_bronze_tb_curso.sql` and `13_tb_curso.sql` exist under `src/pipeline/02_silver/`.
- **Do not run** `generate_database_data(type_of_data='update row')` or `'delete row'`
  (spec, Clarifications 2026-10-28).
- **Free Edition**: stop the SQL warehouse (`databricks warehouses stop f796ffb64302b6ba`)
  only when no query is running, and wait about 4 minutes after the previous update.

## 1. Before the run

```sql
SELECT change_type, count(*) AS n, count(DISTINCT curso_uuid) AS cursos,
       count_if(curso_uuid != md5(nome_curso)) AS chave_diferente
FROM workspace.bronze.dados_database GROUP BY change_type;
```

Expected on 2026-10-28: `insert`, 3, 3, 0, and no other change type.

## 2. Upload, dry run, run

| Step | Command | Expected |
|---|---|---|
| Upload | `databricks workspace import-dir src/pipeline /Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline --overwrite --profile databricks-free` | `02_silver/` lists `01_` to `13_`, all `FILE` |
| Dry run | `databricks pipelines start-update <pipeline_id> --validate-only --profile databricks-free` | `COMPLETED`; `vw_bronze_tb_curso`, `tb_curso` and `silver_tb_curso_flow` are defined |
| Run | `databricks pipelines start-update <pipeline_id> --profile databricks-free` | `COMPLETED`, no failed flow |

## 3. Contents of `tb_curso`

```sql
SELECT curso_uuid, nome_curso, nivel_curso, valor_curso, origem, data_carga
FROM workspace.silver.tb_curso ORDER BY valor_curso;

SELECT count(*) AS linhas, count(DISTINCT curso_uuid) AS cursos,
       count_if(origem != 'DATABASE' OR origem IS NULL) AS origem_fora,
       count_if(data_carga IS NULL) AS sem_data_carga
FROM workspace.silver.tb_curso;

SELECT concat_ws(', ', collect_list(concat(column_name, ' ', full_data_type))) FROM (
  SELECT column_name, full_data_type FROM workspace.information_schema.columns
  WHERE table_schema = 'silver' AND table_name = 'tb_curso' ORDER BY ordinal_position);

-- Sales and accesses join the catalog
SELECT
  (SELECT count(*) FROM workspace.silver.tb_venda v
   LEFT ANTI JOIN workspace.silver.tb_curso c ON v.curso_uuid = c.curso_uuid)  AS vendas_sem_curso,
  (SELECT count(*) FROM workspace.silver.tb_acesso a
   LEFT ANTI JOIN workspace.silver.tb_curso c ON a.curso_uuid = c.curso_uuid
   WHERE a.curso_uuid IS NOT NULL)                                            AS acessos_sem_curso;
```

Expected:
- three rows: `beginner` `247.00`, `intermediate` `997.00`, `advanced` `2497.00`, each
  with `origem = 'DATABASE'`;
- `linhas` = `cursos` = 3; `origem_fora` = `sem_data_carga` = 0;
- the six columns of the data model, `valor_curso decimal(9,2)`, and none of
  `change_type`, `timestamp_change`, `processing_time`, `source_file_name`,
  `_rescued_data`. Record the column order;
- `vendas_sem_curso` = `acessos_sem_curso` = 0;
- `SHOW TBLPROPERTIES workspace.silver.tb_curso ('quality')` is `silver`.

## 4. Expectations, from the event log

Use feature 004's quickstart step 4 queries for the update of step 2. Expected for dataset
`tb_curso`: `check_curso_uuid`, `check_nome_curso` and `check_valor_curso` each passed 3,
failed 0. If the update's events carry no metrics, read them from the update that first
processed the rows (feature 007's notes, T014).

## 5. Incremental behavior

Run another update with no new landing data. Expected: `silver_tb_curso_flow` applies 0
changes and step 3's results are unchanged.

## 6. At the talk (owner)

Not run during implementation. Between each step, run a pipeline update.

| Step | Action | Expected in `tb_curso` |
|---|---|---|
| 1 | `generate_database_data(type_of_data='update row')` | 3 rows; the beginner course at `147.00`, with a new `data_carga`; no row at `247.00` |
| 2 | `generate_database_data(type_of_data='delete row')` | 2 rows; no beginner course; the other two unchanged |

After the talk, `vendas_sem_curso` and `acessos_sem_curso` of step 3 become the sales and
accesses of the deleted course. That is expected; gold keeps the course's history.
