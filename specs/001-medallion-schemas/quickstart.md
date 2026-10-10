# Quickstart: Validating the Medallion Schemas Setup

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-10

How to run the setup and prove it meets the spec. The report columns and check names are
defined in [contracts/setup-and-verify.md](contracts/setup-and-verify.md); the expected
state is in [data-model.md](data-model.md).

## Prerequisites

- Databricks CLI installed and a profile authenticated against the Free Edition workspace
  as `arthur.luz@dataslight.com.br`. List profiles with `databricks auth profiles` and
  choose one; every command below takes it explicitly.
- Run commands from the repository root.

```bash
PROFILE=<your-profile>
databricks current-user me --profile $PROFILE        # must show arthur.luz@dataslight.com.br
```

## Scenario 1: first run creates the schemas (User Story 1)

Starting state: `bronze`, `silver` and `gold` do not exist.

```bash
databricks experimental aitools tools query setup/01_schemas_verify.sql --profile $PROFILE
```

Expected before setup: three `schema_existe` rows with `FAIL`, and no error.

```bash
databricks experimental aitools tools query setup/01_schemas.sql --profile $PROFILE
```

Expected: exit code 0 and a report with 12 `PASS` rows, no `FAIL` row, and no `revogado`
row.

```bash
databricks schemas list workspace --profile $PROFILE
```

Expected: `bronze`, `silver`, `gold`, `default` and `information_schema`; the first three
owned by `arthur.luz@dataslight.com.br`, each with its description.

## Scenario 2: access is restricted to the owner (User Story 2)

```bash
databricks experimental aitools tools query setup/01_schemas_verify.sql --profile $PROFILE
```

Expected:

- three `acesso_direto` rows with `PASS`, each naming only
  `arthur.luz@dataslight.com.br`;
- `acesso_herdado` rows, if any, are `INFO` (today: `USE_CATALOG` for the workspace users
  group, which gives no access to schema contents);
- one `dono_catalogo` row, `INFO`, naming the workspace admins group.

Confirm full control by creating and removing a throwaway object in each schema:

```bash
for s in bronze silver gold; do
  databricks experimental aitools tools query \
    "CREATE TABLE workspace.$s.zz_teste_acesso (id INT)" \
    "DROP TABLE workspace.$s.zz_teste_acesso" --profile $PROFILE
done
```

Expected: both statements succeed for all three schemas.

**Refusal for other identities (SC-003)**: the workspace has a single user, so this is
shown by the report (no grant to anyone else) and not by an attempt. If a second user ever
exists, sign in as that user and run `SHOW TABLES IN workspace.bronze`; it must fail with
a permission error for each of the three schemas.

## Scenario 3: the setup is repeatable (User Story 3)

**Second run changes nothing**

```bash
databricks experimental aitools tools query setup/01_schemas.sql --profile $PROFILE
```

Expected: exit code 0, the same 12 `PASS` rows, no `revogado` row.

**Contents survive a re-run**

```bash
databricks experimental aitools tools query \
  "CREATE TABLE workspace.bronze.zz_teste_reexecucao AS SELECT 1 AS id" --profile $PROFILE
databricks experimental aitools tools query setup/01_schemas.sql --profile $PROFILE
databricks experimental aitools tools query \
  "SELECT count(*) AS linhas FROM workspace.bronze.zz_teste_reexecucao" --profile $PROFILE
```

Expected: `linhas` is 1. Then remove the test table:

```bash
databricks experimental aitools tools query \
  "DROP TABLE workspace.bronze.zz_teste_reexecucao" --profile $PROFILE
```

**A missing schema is recreated alone**

Drop one empty schema, run the setup, and check that only that schema's creation time
changed. Use `silver`, and only while it is empty:

```bash
databricks experimental aitools tools query "DROP SCHEMA workspace.silver" --profile $PROFILE
databricks experimental aitools tools query setup/01_schemas.sql --profile $PROFILE
```

Expected: 12 `PASS` rows; `bronze` and `gold` untouched.

**An extra grant is removed**

```bash
databricks experimental aitools tools query \
  "GRANT USE SCHEMA ON SCHEMA workspace.gold TO \`users\`" --profile $PROFILE
databricks experimental aitools tools query setup/01_schemas_verify.sql --profile $PROFILE
```

Expected: the `acesso_direto` row for `workspace.gold` is `FAIL` and names `users`.

```bash
databricks experimental aitools tools query setup/01_schemas.sql --profile $PROFILE
```

Expected: one `revogado` row (`workspace.gold`, `users`, `USE SCHEMA`) and 12 `PASS` rows.

## Scenario 4: refusals (edge cases)

| Case | How to provoke | Expected |
|---|---|---|
| Wrong identity | run the setup with a profile authenticated as someone else | error containing `must be run as arthur.luz@dataslight.com.br`; no schema created |
| Schema owned by someone else | not reproducible with one user; covered by review of precondition P3 | error naming the schema and its owner; no change |
| Missing permission or catalog | run against a workspace without the `workspace` catalog | error containing `catalog workspace not found`; no change |

## Done when

- Scenarios 1 to 3 give the expected results.
- The final verification report has no `FAIL` row.
- `doc/getting-started.md` points to the setup script instead of listing manual
  `CREATE SCHEMA` statements (FR-014).
