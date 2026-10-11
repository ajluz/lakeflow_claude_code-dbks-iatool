# Quickstart: Validating the Bronze Ingestion

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-11

How to run the three definitions and prove they meet the spec. The definitions and the
pipeline settings are fixed in [contracts/bronze-tables.md](contracts/bronze-tables.md);
the expected columns are in [data-model.md](data-model.md).

## Prerequisites

- Features 001 and 002 are in place: the combined environment check shows no `FAIL` row.
- All three landing folders hold data. Check with:

```bash
PROFILE=<your-profile>
for d in stream files database; do
  echo "$d: $(databricks fs ls dbfs:/Volumes/workspace/bronze/landing/$d --profile $PROFILE | grep -vc '^_')"
done
```

  Each line must show at least 1. If a folder is missing or empty, generate its data with
  the project's generators before continuing.
- `jq` installed. Run commands from the repository root.

```bash
WS=/Workspace/Users/arthur.luz@dataslight.com.br/lakeflow_dev/src/pipeline
q() { databricks experimental aitools tools query "$1" --profile $PROFILE; }
```

## Scenario 1: create the pipeline and run it (User Story 1)

```bash
databricks workspace import-dir src/pipeline $WS --overwrite --profile $PROFILE
PIPELINE_ID=$(databricks pipelines create --json @explorations/setup/03_pipeline_dev.json \
  --profile $PROFILE | jq -r .pipeline_id)
```

Dry run first; it must finish as `COMPLETED` without creating any table:

```bash
databricks pipelines start-update $PIPELINE_ID --validate-only --profile $PROFILE
```

Then the real run, polling the update until it ends:

```bash
UPDATE_ID=$(databricks pipelines start-update $PIPELINE_ID --profile $PROFILE | jq -r .update_id)
while :; do
  STATE=$(databricks pipelines get-update $PIPELINE_ID $UPDATE_ID --profile $PROFILE | jq -r .update.state)
  echo "$(date +%H:%M:%S) $STATE"
  case "$STATE" in COMPLETED|FAILED|CANCELED) break;; esac
  sleep 30
done
```

Expected: `COMPLETED`. On `FAILED`, read the cause from the events as shown in the
contract; do not simply run again.

```bash
databricks tables list workspace bronze --profile $PROFILE
```

Expected: `dados_api`, `dados_files` and `dados_database`.

**Row counts match the landing files (SC-002)**. For each table, the two numbers returned
must be equal:

```bash
q "SELECT (SELECT count(*) FROM workspace.bronze.dados_api) AS tabela,
          (SELECT count(*) FROM read_files('/Volumes/workspace/bronze/landing/stream/', format => 'json')) AS arquivos"
q "SELECT (SELECT count(*) FROM workspace.bronze.dados_files) AS tabela,
          (SELECT count(*) FROM read_files('/Volumes/workspace/bronze/landing/files/', format => 'csv', header => true, sep => ',')) AS arquivos"
q "SELECT (SELECT count(*) FROM workspace.bronze.dados_database) AS tabela,
          (SELECT count(*) FROM read_files('/Volumes/workspace/bronze/landing/database/', format => 'csv', header => true, sep => ',')) AS arquivos"
```

**Nesting is preserved**:

```bash
q "SELECT payload.info_produto.product_name, count(*) FROM workspace.bronze.dados_api GROUP BY ALL"
```

Expected: course names (and nulls for visits without a product), with no error.

## Scenario 2: lineage columns and the quality property (User Story 2)

For each of the three tables:

```bash
q "SELECT count(*) AS linhas,
          count_if(processing_time IS NULL) AS sem_processing_time,
          count_if(source_file_name IS NULL) AS sem_source_file_name,
          count(DISTINCT source_file_name) AS arquivos
   FROM workspace.bronze.dados_database"
q "SHOW TBLPROPERTIES workspace.bronze.dados_database ('quality')"
q "DESCRIBE workspace.bronze.dados_database"
```

Expected:

- both null counts are 0 (SC-003);
- `arquivos` equals the number of data files in the source folder (when comparing paths
  with a batch read, strip the `dbfs:` prefix the batch read adds), and every
  `source_file_name` starts with `/Volumes/workspace/bronze/landing/` followed by
  that source's folder (SC-004);
- `quality` is `bronze` (SC-008);
- the columns are `processing_time`, `source_file_name`, the source columns of the data
  model, and `_rescued_data` (SC-005).

## Scenario 3: only new files are ingested (User Story 3)

**A run with no new files adds nothing (SC-006)**. Note the three counts, run the update
again as in Scenario 1, and compare:

```bash
q "SELECT 'dados_api' AS t, count(*) AS n FROM workspace.bronze.dados_api
   UNION ALL SELECT 'dados_files', count(*) FROM workspace.bronze.dados_files
   UNION ALL SELECT 'dados_database', count(*) FROM workspace.bronze.dados_database"
```

Expected: the same three numbers before and after.

**One new file adds exactly its records (SC-007)**. Deliver one change to the course
catalog, in the shape the generator writes:

```bash
cat > /tmp/zz_teste_bronze_update.csv <<'EOF'
curso_uuid,nome_curso,nivel_curso,valor_curso,change_type,timestamp_change
6532cdca76d4a7e6f10f71be7eb74668,Construindo um Data Lakehouse com SQL e DLT,beginner,147.0,update,2026-10-11T23:59:59.000Z
EOF
databricks fs cp /tmp/zz_teste_bronze_update.csv \
  dbfs:/Volumes/workspace/bronze/landing/database/zz_teste_bronze_update.csv --profile $PROFILE
```

Run the update again and repeat the count query.

Expected: `dados_database` grew by exactly 1; the other two are unchanged; the new row's
`processing_time` is later than that of the first three rows, and its `source_file_name`
ends with `zz_teste_bronze_update.csv`.

## Clean-up of the test row (owner's decision)

Bronze is append-only, so the test row stays unless the table is rebuilt. To return
`dados_database` to the original rows, remove the test file and fully refresh that one
table. A full refresh discards what was ingested, so it is run only with the owner's
approval. The CLI has no flag for refreshing a single table; the selection goes in the
request body:

```bash
databricks fs rm dbfs:/Volumes/workspace/bronze/landing/database/zz_teste_bronze_update.csv --profile $PROFILE
databricks pipelines start-update $PIPELINE_ID \
  --json '{"full_refresh_selection": ["dados_database"]}' --profile $PROFILE
```

Expected afterwards: `dados_database` has the same count as its landing files again, and
the row counts and latest `processing_time` of the other two tables are unchanged.

Keeping the row is also valid: it is the same change the talk's change-data-capture demo
makes.

## Done when

- Scenarios 1 to 3 give the expected results.
- The three definition files contain nothing from the contract's forbidden list.
- `doc/pipeline-reference.md` describes the three bronze tables as built (FR-016).
