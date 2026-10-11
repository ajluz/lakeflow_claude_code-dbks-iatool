# Research: Landing Volume in Bronze

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-11

Findings marked *observed* were read from the target environment on 2026-10-11 with
read-only queries (profile `databricks-free`, host `dbc-7e0f02e0-ff06`). Nothing was
changed there. Decisions that repeat feature 001 refer to
[its research](../001-medallion-schemas/research.md) instead of restating it.

## State of the target environment (observed)

| Fact | Value |
|---|---|
| Schema `workspace.bronze` | exists, owned by `arthur.luz@dataslight.com.br` |
| Volumes in `workspace.bronze` | none |
| Tables or views in `workspace.bronze` | none, so nothing named `landing` is in the way |
| Other volumes in the catalog | one managed volume in `default`, unrelated to this project |
| `workspace.information_schema.volumes` | has `volume_schema`, `volume_name`, `volume_type`, `volume_owner`, `comment`, `storage_location` |
| `workspace.information_schema.volume_privileges` | has `grantee`, `volume_schema`, `volume_name`, `privilege_type`, `inherited_from` |
| CLI batch mode | several files in one `query` call are accepted only with `--output json`; the result is an array with one object per file, each holding `columns` and `rows` |
| `jq` | installed on the owner's machine |

## Decision 1: how the volume is created

**Decision**: one idempotent SQL script, `explorations/setup/02_landing_volume.sql`,
written as a single SQL scripting compound statement, in the same form as
`explorations/setup/01_schemas.sql`.

**Rationale**: the needs are the same as in feature 001 (check before changing, loop over
existing grants, stop with a named error), and that script's structure was validated
against this workspace. Using the same form keeps the two steps readable as a pair.
`CREATE VOLUME IF NOT EXISTS` never replaces an existing volume, which is what protects
the files on a re-run (FR-009, FR-010).

**Alternatives considered**:
- *Add the volume to `01_schemas.sql`*. Rejected: that script is a finished, validated
  deliverable of feature 001, and one file per step keeps each step independently
  runnable and verifiable.
- *Bundle resource (`resources.volumes`)*. Rejected for the reasons given in feature 001:
  development-mode name prefixing and removal of the volume, with its files, on
  `bundle destroy`.
- *`CREATE OR REPLACE VOLUME`*. Rejected: it would discard the files.

## Decision 2: storage

**Decision**: a managed volume. The script gives no `LOCATION`.

**Rationale**: FR-002. Free Edition needs no external location, and a managed volume lives
at the fixed path `/Volumes/workspace/bronze/landing`, which is the path the data
generators and the constitution already use.

**An existing external volume is reported, not changed**: if a volume named `landing`
already exists with a type other than `MANAGED`, the verification shows a `FAIL` row for
storage. The setup does not drop or convert it, since that would lose or strand files.

## Decision 3: access rule

**Decision**: same mechanism as feature 001, applied to the volume. The script makes sure
the owner is `arthur.luz@dataslight.com.br`, grants that identity `ALL PRIVILEGES` on the
volume, and revokes every privilege granted directly on the volume to anyone else, found in
`workspace.information_schema.volume_privileges` where `inherited_from = 'NONE'`.

**Rationale**: the explicit grant makes "exactly one identity" readable from the grant
list (SC-002), and reading grants from the information schema handles grants nobody
anticipated.

**Inherited access**: rows of `volume_privileges` whose `inherited_from` is not `NONE`,
for grantees other than the owner, are reported. They are `INFO` when the privilege alone
gives no access to files (`USE_CATALOG`, `USE_SCHEMA`, `BROWSE`) and `FAIL` otherwise.
Catalog-level grants and the catalog owner are already reported by step 1 and are not
repeated.

**Not observed yet**: the owner holds `ALL PRIVILEGES` on the `bronze` schema, granted in
feature 001. Whether that appears in `volume_privileges` as an inherited row for the
volume could not be seen, because no volume exists in `bronze` yet. The design does not
depend on the answer: inherited rows for the owner are ignored, and the direct grant is
made either way.

## Decision 4: preconditions

**Decision**: the script checks all of the following before changing anything and stops
with a message naming the first that fails:

1. the schema `workspace.bronze` exists; otherwise the message says to run
   `explorations/setup/01_schemas.sql` first;
2. `current_user()` is `arthur.luz@dataslight.com.br`;
3. the schema `workspace.bronze` is owned by that identity;
4. no table or view named `landing` exists in `workspace.bronze`;
5. if a volume named `landing` already exists, it is owned by that identity.

**Rationale**: these are the refusals required by FR-012 and the spec's edge cases. The
script never creates the schema: that belongs to step 1, and creating it here would skip
the access rule that step applies.

**Alternatives considered**:
- *Create `bronze` when missing*. Rejected, as above.
- *Call the step 1 script from step 2*. Rejected: SQL scripts cannot include one another,
  and a silent dependency would hide which step failed.

## Decision 5: verification, alone and together with step 1

**Decision**: a read-only script, `explorations/setup/02_landing_volume_verify.sql`,
returns a report with the same five columns as step 1 (`ordem`, `verificacao`, `objeto`,
`resultado`, `detalhe`). Its `ordem` values start at 110, above those of step 1. The
"environment ready up to this point" check of FR-014 is one CLI call that runs both verify
files and prints their rows as one table:

```bash
databricks experimental aitools tools query \
  explorations/setup/01_schemas_verify.sql \
  explorations/setup/02_landing_volume_verify.sql \
  --profile <profile> --output json | jq -r '.[].rows[] | @tsv'
```

**Rationale**: the same columns and non-overlapping `ordem` ranges make the two reports
read as one. Running the two files in one call avoids a third copy of the step 1 query,
which already exists twice (in the setup and verify scripts of step 1).

**Alternatives considered**:
- *One cumulative verify file that repeats the step 1 checks*. Rejected: a third copy of a
  200-line query to keep identical by hand.
- *A persistent view holding the report*. Rejected: it would create an object in the
  catalog that is not part of the medallion model.
- *Searching the JSON output for the word `FAIL`*. Rejected: the output includes the SQL
  text, which contains that word. Rows must be selected with `jq`.

## Decision 6: proving that files can be written and read

**Decision**: the quickstart copies a small local file to the volume and back with
`databricks fs cp`, using the `dbfs:/Volumes/workspace/bronze/landing/` path form, and
compares the two. The test file is removed afterwards.

**Rationale**: SC-004 asks for a round trip. The CLI needs the `dbfs:` prefix even for
volume paths. This also proves the path the generators will use.

## Decision 7: description and file location

**Decision**: the volume's `COMMENT` is in Portuguese, like the schema descriptions:
`Landing zone: arquivos de origem como chegaram, uma pasta por origem.` It is re-applied
only when it differs. The two files live in `explorations/setup/` with the prefix `02_`.

**Rationale**: constitution v1.5.0 names `explorations/setup/` for auxiliary setup code,
numbered in run order.

## Carried over from feature 001

- Dynamic statements that embed text use double-quoted literals; `''` is not an escaped
  quote in this SQL dialect.
- The information schema reflects a `REVOKE` within the same compound statement.
- A stray grant for testing goes to `account users`; the workspace-local `users` group is
  not a valid principal and the system workspace-users group cannot receive grants.
- Refusal for other identities is shown by the absence of grants, because the workspace
  has a single user.

## Open questions

None that block the design. Two facts will be confirmed during implementation and are
handled either way: how the schema-level grant shows up on the volume (Decision 3), and
the exact privilege names `volume_privileges` returns for `ALL PRIVILEGES`.
