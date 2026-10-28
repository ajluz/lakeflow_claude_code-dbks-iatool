# Getting started

How to run the demo end to end in a Databricks workspace. It was built for
Databricks Free Edition, whose default catalog is `workspace`.

Read [known-issues.md](known-issues.md) first: a few references in the code
point at a different catalog and need adjusting before a clean run.

## Prerequisites

- A Databricks workspace with Unity Catalog and serverless pipelines
- A catalog named `workspace`
- Permission to create schemas, volumes, tables and pipelines in it

### Create the schemas

The `bronze`, `silver` and `gold` schemas are created by a script that can be run
again at any time. It makes `arthur.luz@dataslight.com.br` the owner and the only
identity with access, never drops anything, and refuses to run as anyone else.
Choose your CLI profile and pass it explicitly:

```bash
databricks experimental aitools tools query explorations/setup/01_schemas.sql --profile <profile>
databricks experimental aitools tools query explorations/setup/01_schemas_verify.sql --profile <profile>
```

Both commands print the same verification report. The environment is ready when
the report has no `FAIL` row; a clean setup shows 12 `PASS` rows. The second
command is read-only and can be used on its own to check the environment.

### Create the landing volume

The `landing` volume, where source files arrive, is created in `workspace.bronze` by a
second script. Run it after the schemas step:

```bash
databricks experimental aitools tools query explorations/setup/02_landing_volume.sql --profile <profile>
```

It creates a managed volume owned by `arthur.luz@dataslight.com.br`, with no access for
anyone else. It can be run again at any time: it never drops or replaces the volume, so
files already in it are kept. It refuses to run if the `bronze` schema is missing. The
report it prints must have no `FAIL` row; a clean run shows 6 `PASS` rows.

The folders inside the volume, one per source, are created by the data generators.

### Check the whole environment

One command runs the read-only verification of both steps and prints one table. It needs
`jq`:

```bash
databricks experimental aitools tools query \
  explorations/setup/01_schemas_verify.sql \
  explorations/setup/02_landing_volume_verify.sql \
  --profile <profile> --output json | jq -r '.[].rows[] | @tsv'
```

The environment is ready when no row says `FAIL`; a clean environment shows 18 `PASS` rows.

## 1. Import the code

Import the repository into the workspace as a Git folder, or upload
[explorations/](../explorations/) to run the notebooks. The pipeline source in
[src/pipeline/](../src/pipeline/) is uploaded by the commands of step 3.

## 2. Generate the source data

Open [explorations/user_case.py](../explorations/user_case.py) and run the
**Setup** section.

1. `%run "./functions"` installs `dbldatagen`, defines the generators and
   creates `workspace.gold.dim_tempo`. Run it once per environment (see
   [known-issues.md](known-issues.md#dim_tempo-is-reloaded-on-every-run)).
2. In the next cell, the file and database generators are commented out. On a
   first run, uncomment them so all three sources have data:

```python
generate_files_data(number_rows=100000)
generate_database_data(type_of_data='initial setup')
query = generate_api_data(number_rows=3876831, run_as_batch=True)
```

Keep `run_as_batch=True` on Free Edition. See
[data-generation.md](data-generation.md) for what each call writes.

## 3. Create and run the pipeline

The pipeline source is [src/pipeline/](../src/pipeline/), and the settings of
the development pipeline are in
[explorations/setup/03_pipeline_dev.json](../explorations/setup/03_pipeline_dev.json).
Each of the three landing folders must already hold data (step 2).

Upload the source and create the pipeline once:

```bash
WS=/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline
databricks workspace import-dir src/pipeline $WS --overwrite --profile <profile>
PIPELINE_ID=$(databricks pipelines create --json @explorations/setup/03_pipeline_dev.json \
  --profile <profile> -o json | jq -r .pipeline_id)
```

Check the code without touching data, then run:

```bash
databricks pipelines start-update $PIPELINE_ID --validate-only --profile <profile>

UPDATE_ID=$(databricks pipelines start-update $PIPELINE_ID --profile <profile> -o json | jq -r .update_id)
while :; do
  STATE=$(databricks pipelines get-update $PIPELINE_ID $UPDATE_ID --profile <profile> -o json | jq -r .update.state)
  echo "$(date +%H:%M:%S) $STATE"
  case "$STATE" in COMPLETED|FAILED|CANCELED) break;; esac
  sleep 15
done
```

After a code change, upload again with the same `import-dir` command and start
a new update. A normal run never uses `--full-refresh`: it discards what was
ingested and reads every file again.

If an update fails, the cause is in the pipeline's events:

```bash
databricks pipelines list-pipeline-events $PIPELINE_ID --profile <profile> -o json \
  | jq '[.[] | select(.level=="ERROR") | (.error.exceptions[0].message // .message)] | .[0:3]'
```

On Free Edition, an update can fail with `RESOURCE_EXHAUSTED` when other
serverless compute is running, such as a SQL warehouse that a recent query left
awake. Stop it, wait about a minute and start the update again.

Today the pipeline has the bronze layer only. The graph in
[lakeflow_architecture.png](lakeflow_architecture.png) shows the earlier, complete
pipeline.

## 4. Explore the results

The rest of `user_case.py` queries each layer in turn.

**Bronze** — the three raw tables, with commented filters that isolate the bad
records each expectation targets.

**Silver** — quarantine, access, user, sales and course tables. Compare row
counts against the pipeline's data quality tab to see what each expectation
dropped or recorded.

**Gold** — dimensions, the fact table and two example business questions:
revenue for a month by access location and discount, and the access-to-sale
conversion rate from `obt_acesso`.

## 5. Change data capture demo

The notebook shows how the two `AUTO CDC` flows react to changes in the course
catalog. After each generator call, run the pipeline again, then re-run the
comparison cells.

| Step | Call | `silver.tb_curso` (SCD 1) | `gold.dim_curso` (SCD 2) |
|---|---|---|---|
| Update | `generate_database_data(type_of_data='update row')` | price overwritten to 147.00 | old row closed with `__END_AT`, new row opened |
| Delete | `generate_database_data(type_of_data='delete row')` | row removed | current row closed with `__END_AT` |

`bronze.dados_database` keeps every change event in both cases.

## 6. Clean up

[explorations/clean_up_env.ipynb](../explorations/clean_up_env.ipynb) removes
the landing folders and the stream checkpoint, then drops every non-temporary
table in the `bronze`, `silver` and `gold` schemas.

It is destructive and currently targets the `dataslight_dev` catalog, not
`workspace`. Change the catalog name in the notebook before running it against
this setup, and delete the pipeline itself from the UI.
