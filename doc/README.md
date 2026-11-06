# Data's Light Academy — Lakeflow demo

Demo project for the Databricks User Group RJ talk (2026-09-07). It builds a small
lakehouse for a fictional online course company, **Data's Light Academy**, using
**Lakeflow Spark Declarative Pipelines** written entirely in SQL, on top of the
medallion architecture (bronze → silver → gold).

The pipeline ingests three sources (a streaming API, partner CSV files and a
database CDC feed), validates and conforms them, and publishes a star schema plus
a one-big-table for analytics.

## Documentation

| Document | What it covers |
|---|---|
| [architecture.md](architecture.md) | Sources, layers, the dataset graph and the Lakeflow features each step demonstrates |
| [pipeline-reference.md](pipeline-reference.md) | Every dataset in the pipeline: type, source, columns, expectations |
| [data-generation.md](data-generation.md) | The synthetic data generators and the bad records they inject on purpose |
| [getting-started.md](getting-started.md) | Prerequisites, how to run the demo end to end, and how to clean up |
| [known-issues.md](known-issues.md) | Inconsistencies and likely bugs found in the code while documenting it |

## Repository layout

```
lakeflow/
├── src/                     Project code: what the pipeline deploys and runs
│   └── pipeline/            Pipeline source (SQL), one file per dataset
│       ├── 01_bronze/       Auto Loader ingestion into streaming tables
│       │   ├── 01_dados_api.sql       Site events, from landing/stream/ (JSON)
│       │   ├── 02_dados_files.sql     Corporate sales, from landing/files/ (CSV)
│       │   └── 03_dados_database.sql  Course catalog changes, from landing/database/ (CSV)
│       ├── 02_silver/       Validation, quarantine and conformed tables
│       │   ├── 01_vw_bronze_dados_api.sql    Boundary view: bronze events minus source_file_name, _rescued_data
│       │   ├── 02_vw_bronze_dados_files.sql  Boundary view: bronze sales minus source_file_name, _rescued_data
│       │   ├── 03_temp_tb_validacao_api.sql  Private validation table: 3 rules, fl_registro_invalido
│       │   ├── 04_tb_quarentena.sql          Quarantine of the flagged API events
│       │   ├── 05_tb_acesso.sql              Conformed access table: drop / record / commented fail rules
│       │   ├── 06_vw_silver_tb_usuario_api.sql    Flow view: API users in tb_usuario's columns
│       │   ├── 07_vw_silver_tb_usuario_files.sql  Flow view: files users in tb_usuario's columns
│       │   ├── 08_tb_usuario.sql             User table: two append flows (SELECT * from each flow view), drop / record rules
│       │   ├── 09_vw_silver_tb_venda_api.sql    Flow view: API sales in tb_venda's columns
│       │   ├── 10_vw_silver_tb_venda_files.sql  Flow view: files sales in tb_venda's columns
│       │   ├── 11_tb_venda.sql               Sales table: two append flows, five record-only rules
│       │   ├── 12_vw_bronze_tb_curso.sql     Course feed view: boundary + price as DECIMAL, origem, data_carga
│       │   └── 13_tb_curso.sql               Course table: AUTO CDC SCD type 1 (key, sequence, delete)
│       └── 03_gold/         Dimensional model: dimensions and facts
│           ├── 01_vw_gold_dim_usuario_tb_usuario.sql  Flow view: stable hash surrogate key
│           ├── 02_dim_usuario.sql        User dimension: AUTO CDC SCD type 1, unknown / not-applicable members
│           ├── 03_dim_codigos.sql        Junk dimension: materialized view, cross join of code values, deterministic key
│           ├── 04_vw_gold_dim_curso_dados_database.sql  Flow view: surrogate key per course version
│           ├── 05_vw_gold_dim_curso_membros.sql         Course dimension members -1 / -2
│           └── 06_dim_curso.sql          Course dimension: AUTO CDC SCD type 2, members by a once-only flow
├── explorations/            Auxiliary code: setup, generators and notebooks
│   ├── setup/               Environment preparation, run by hand in step order
│   │   ├── 01_schemas.sql                Creates the schemas and applies the access rule
│   │   ├── 01_schemas_verify.sql         Read-only verification report for the schemas
│   │   ├── 02_landing_volume.sql         Creates the landing volume and applies the access rule
│   │   ├── 02_landing_volume_verify.sql  Read-only verification report for the volume
│   │   ├── 03_pipeline_dev.json          Settings of the development pipeline
│   │   └── 04_dim_tempo.sql              Creates and fills the calendar dimension gold.dim_tempo
│   ├── functions.py         Data generators
│   ├── user_case.py         Walkthrough: case study, setup, queries per layer
│   └── clean_up_env.ipynb   Drops tables and landing files
├── data/                    Local tooling state, no datasets
└── doc/                     This documentation
    └── lakeflow_architecture.png   Screenshot of the pipeline graph
```

The numeric prefix of each layer folder under `src/pipeline/`, and of each file
inside it (`NN_<dataset>.sql`, numbered from `01` per folder), is for reading
order only. A declarative pipeline resolves the execution order from the
dependencies between datasets. Silver holds the API validation and quarantine so
far; gold is not built yet.

## At a glance

| | |
|---|---|
| Catalog / schemas | `workspace.bronze`, `workspace.silver`, `workspace.gold` |
| Landing volume | `/Volumes/workspace/bronze/landing/{stream,files,database}` |
| Pipeline datasets | 3 bronze streaming tables; in silver, 7 streaming views, 1 private streaming table and 5 streaming tables; in gold, 3 streaming views, 2 streaming tables and 1 materialized view (plus `dim_tempo`, created outside the pipeline) |
| Created outside the pipeline | `workspace.gold.dim_tempo` (by `explorations/setup/04_dim_tempo.sql`) |
| Target environment | Databricks Free Edition (streaming simulated with `availableNow`) |

Object names, column names and code comments are in Portuguese, as in the talk.
