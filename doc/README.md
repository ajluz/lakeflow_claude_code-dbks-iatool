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
│       └── 02_silver/       Validation and quarantine (API source so far)
│           ├── 01_vw_bronze_dados_api.sql    Boundary view: bronze events minus source_file_name, _rescued_data
│           ├── 02_temp_tb_validacao_api.sql  Private validation table: 3 rules, fl_registro_invalido
│           └── 03_tb_quarentena.sql          Quarantine of the flagged API events
├── explorations/            Auxiliary code: setup, generators and notebooks
│   ├── setup/               Environment preparation, run by hand in step order
│   │   ├── 01_schemas.sql                Creates the schemas and applies the access rule
│   │   ├── 01_schemas_verify.sql         Read-only verification report for the schemas
│   │   ├── 02_landing_volume.sql         Creates the landing volume and applies the access rule
│   │   ├── 02_landing_volume_verify.sql  Read-only verification report for the volume
│   │   └── 03_pipeline_dev.json          Settings of the development pipeline
│   ├── functions.py         Data generators + creation of gold.dim_tempo
│   ├── user_case.ipynb      Walkthrough: case study, setup, queries per layer
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
| Pipeline datasets | 3 bronze streaming tables; in silver, 1 streaming view, 1 private streaming table and 1 streaming table; gold not built yet |
| Created outside the pipeline | `workspace.gold.dim_tempo` (by `functions.py`) |
| Target environment | Databricks Free Edition (streaming simulated with `availableNow`) |

Object names, column names and code comments are in Portuguese, as in the talk.
