# Quickstart: Validating the Landing Volume Setup

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-11

How to run the setup and prove it meets the spec. Check names and report columns are
defined in [contracts/setup-and-verify.md](contracts/setup-and-verify.md); the expected
state is in [data-model.md](data-model.md).

## Prerequisites

- Step 1 is done: the `bronze`, `silver` and `gold` schemas exist and
  `explorations/setup/01_schemas_verify.sql` reports no `FAIL` row.
- Databricks CLI authenticated against the Free Edition workspace as
  `arthur.luz@dataslight.com.br`. Choose the profile; every command takes it explicitly.
- `jq` installed, for the combined check.
- Run commands from the repository root.

```bash
PROFILE=<your-profile>
SETUP=explorations/setup
VOL=dbfs:/Volumes/workspace/bronze/landing
```

## Scenario 1: first run creates the volume (User Story 1)

Starting state: no volume named `landing` in `workspace.bronze`.

```bash
databricks experimental aitools tools query $SETUP/02_landing_volume_verify.sql --profile $PROFILE
```

Expected before setup: `pre_requisito` is `PASS`, `volume_existe` is `FAIL`, no error.

```bash
databricks experimental aitools tools query $SETUP/02_landing_volume.sql --profile $PROFILE
```

Expected: exit code 0 and a report with 6 `PASS` rows, no `FAIL` row, no `revogado` row.

```bash
databricks volumes list workspace bronze --profile $PROFILE
```

Expected: one volume, `landing`, type `MANAGED`, owned by
`arthur.luz@dataslight.com.br`, with its description.

**Round trip of a file (SC-004)**

```bash
echo "teste de escrita $(date)" > /tmp/zz_teste_landing.txt
databricks fs cp /tmp/zz_teste_landing.txt $VOL/zz_teste_landing.txt --profile $PROFILE
databricks fs cp $VOL/zz_teste_landing.txt /tmp/zz_teste_landing_volta.txt --profile $PROFILE
diff /tmp/zz_teste_landing.txt /tmp/zz_teste_landing_volta.txt && echo "conteúdo idêntico"
```

Expected: `conteúdo idêntico`. Keep the file in the volume for Scenario 3.

## Scenario 2: access is restricted to the owner (User Story 2)

```bash
databricks experimental aitools tools query $SETUP/02_landing_volume_verify.sql --profile $PROFILE
```

Expected: `dono` and `acesso_direto` are `PASS` and name only
`arthur.luz@dataslight.com.br`; any `acesso_herdado` row is `INFO`.

**Refusal for other identities (SC-003)**: the workspace has a single user, so this is
shown by the report and not by an attempt. If a second user ever exists, sign in as that
user and run `databricks fs ls $VOL`; it must fail with a permission error.

## Scenario 3: the setup is repeatable (User Story 3)

**Second run changes nothing and keeps the file**

```bash
databricks experimental aitools tools query $SETUP/02_landing_volume.sql --profile $PROFILE
databricks fs cp $VOL/zz_teste_landing.txt /tmp/zz_teste_landing_volta2.txt --profile $PROFILE
diff /tmp/zz_teste_landing.txt /tmp/zz_teste_landing_volta2.txt && echo "arquivo preservado"
```

Expected: 6 `PASS` rows, no `revogado` row, and `arquivo preservado`.

**An extra grant is removed**

```bash
databricks experimental aitools tools query \
  "GRANT READ VOLUME ON VOLUME workspace.bronze.landing TO \`account users\`" --profile $PROFILE
databricks experimental aitools tools query $SETUP/02_landing_volume_verify.sql --profile $PROFILE
```

Expected: `acesso_direto` is `FAIL` and names `account users`.

```bash
databricks experimental aitools tools query $SETUP/02_landing_volume.sql --profile $PROFILE
```

Expected: one `revogado` row naming `account users`, and 6 `PASS` rows. The test file is
still in the volume.

**A removed volume is recreated**

Only with the owner's approval, and only after removing the test file, since dropping a
managed volume deletes its files:

```bash
databricks fs rm $VOL/zz_teste_landing.txt --profile $PROFILE
databricks experimental aitools tools query "DROP VOLUME workspace.bronze.landing" --profile $PROFILE
databricks experimental aitools tools query $SETUP/02_landing_volume.sql --profile $PROFILE
```

Expected: 6 `PASS` rows, and the step 1 report still shows 12 `PASS` rows.

## Scenario 4: refusals (edge cases)

| Case | How to provoke | Expected |
|---|---|---|
| Object named `landing` in the way | with no volume present, create the table `workspace.bronze.landing (id INT)`, run the setup, then drop the table | error containing `an object named landing already exists`; nothing created |
| Schema missing | not provoked: it would mean dropping `bronze`; covered by review of precondition P1 | error containing `run explorations/setup/01_schemas.sql first` |
| Wrong identity, schema or volume owned by someone else | not reproducible with one user; covered by review of P2, P3, P5 | error naming the reason; no change |

## Scenario 5: the environment is ready up to this step (FR-014)

```bash
databricks experimental aitools tools query \
  $SETUP/01_schemas_verify.sql $SETUP/02_landing_volume_verify.sql \
  --profile $PROFILE --output json | jq -r '.[].rows[] | @tsv'
```

Expected: one table with the rows of both steps and no `FAIL`; 18 `PASS` rows.

## Clean up

```bash
databricks fs rm $VOL/zz_teste_landing.txt --profile $PROFILE   # if still present
rm -f /tmp/zz_teste_landing*.txt
```

## Done when

- Scenarios 1 to 3 and 5 give the expected results.
- The volume is empty at the end.
- `doc/getting-started.md` points to the setup script instead of the manual
  `CREATE VOLUME` statement (FR-015).
