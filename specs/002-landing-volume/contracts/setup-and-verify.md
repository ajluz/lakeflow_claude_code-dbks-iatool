# Contract: Landing Volume Setup and Verification Scripts

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-11

Two scripts, in the same form as those of step 1. This document fixes what each accepts,
does, returns and refuses.

## Common interface

| Aspect | Contract |
|---|---|
| Form | each script is one SQL statement, runnable on a Databricks SQL warehouse |
| Invocation | `databricks experimental aitools tools query <file> --profile <profile>`, or pasted into the SQL editor |
| Profile | always chosen and passed by the caller; never stored in the script |
| Parameters | none; the catalog, schema, volume name, description and authorized principal are constants at the top of each script |
| Result | one result set, the verification report defined below |
| Exit | CLI exit code is non-zero when the statement raises an error |

## `explorations/setup/02_landing_volume.sql`

**Purpose**: bring the volume to the compliant state defined in
[../data-model.md](../data-model.md).

### Preconditions (all checked before any change)

| # | Condition | On failure: error message contains |
|---|---|---|
| P1 | the schema `workspace.bronze` exists | `schema workspace.bronze not found` and `run explorations/setup/01_schemas.sql first` |
| P2 | `current_user()` is the authorized principal | `must be run as arthur.luz@dataslight.com.br` and the actual user |
| P3 | `workspace.bronze` is owned by the authorized principal | `schema bronze is owned by <owner>` |
| P4 | no table or view named `landing` exists in `workspace.bronze` | `an object named landing already exists in workspace.bronze` and its type |
| P5 | if a volume named `landing` exists, it is owned by the authorized principal | `volume landing is owned by <owner>` |

When any precondition fails the script raises an error and has changed nothing.

### Effects, in order

1. Create the volume `workspace.bronze.landing` as a managed volume if it does not exist.
2. Set the volume description to the text in the data model, when it differs.
3. Grant `ALL PRIVILEGES` on the volume to the authorized principal.
4. Revoke every privilege granted directly on the volume to any other grantee.

### Guarantees

| # | Guarantee | Requirement |
|---|---|---|
| G1 | Never drops or replaces the volume, and never removes, moves or lists for deletion any file or folder in it. | FR-010 |
| G2 | Never creates, alters or drops a schema, a table or any other volume. | FR-011 |
| G3 | Never changes a grant on the schema or on the catalog. | Assumptions |
| G4 | Running it on a compliant volume changes nothing and succeeds. | FR-009 |
| G5 | Running it on a drifted volume restores compliance and keeps all files. | FR-009 |
| G6 | Reports each privilege it revoked: grantee and privilege. | FR-007 |
| G7 | Ends by returning the verification report. | FR-013 |
| G8 | Gives no storage location; an existing volume of another type is reported, not converted. | FR-002 |

## `explorations/setup/02_landing_volume_verify.sql`

**Purpose**: report the current state on demand. Read-only, and safe to run in any state,
including before either setup step.

| # | Guarantee |
|---|---|
| V1 | Makes no change to the environment. It is a single query, with no scripting block. |
| V2 | Succeeds whether or not the schema or the volume exists; a missing object is a `FAIL` row, not an error. |
| V3 | Returns the verification report. |

## Verification report

One result set with the same columns as step 1, ordered by `ordem`.

| Column | Type | Meaning |
|---|---|---|
| `ordem` | INT | display order; this step uses 110 and above |
| `verificacao` | STRING | check name, from the list below |
| `objeto` | STRING | `workspace.bronze` or `workspace.bronze.landing` |
| `resultado` | STRING | `PASS`, `FAIL` or `INFO` |
| `detalhe` | STRING | the observed value, and for `FAIL` what was expected |

| `ordem` | `verificacao` | Rows | `PASS` when |
|---|---|---|---|
| 110 | `alvo` | 1 | always `INFO`: current user, catalog, metastore |
| 120 | `pre_requisito` | 1 | `workspace.bronze` exists and is owned by the authorized principal |
| 130 | `volume_existe` | 1 | the volume exists |
| 140 | `dono` | 1 | the owner is the authorized principal |
| 150 | `armazenamento` | 1 | the volume type is `MANAGED` |
| 160 | `descricao` | 1 | the description matches the data model |
| 170 | `acesso_direto` | 1 | the authorized principal is the only grantee with a direct grant |
| 180 | `acesso_herdado` | 0 or more | `INFO` for `USE_CATALOG`, `USE_SCHEMA` or `BROWSE`; `FAIL` for any other privilege inherited by another grantee |
| 190 | `revogado` | 0 or more | setup script only, always `INFO`: a privilege removed in this run |

**Result for this step**: compliant when the report has no `FAIL` row; a clean run has 6
`PASS` rows.

## Combined environment check

One call runs the verification of both steps and prints one table (FR-014):

```bash
databricks experimental aitools tools query \
  explorations/setup/01_schemas_verify.sql \
  explorations/setup/02_landing_volume_verify.sql \
  --profile <profile> --output json | jq -r '.[].rows[] | @tsv'
```

**Result for the environment**: ready up to this step when no row has `FAIL` in the fourth
column; a clean environment has 18 `PASS` rows (12 from step 1, 6 from step 2). Rows must
be selected with `jq`: the raw JSON also carries the SQL text, which contains the word
`FAIL`.

## Mapping to the specification

| Spec item | Covered by |
|---|---|
| FR-001, FR-002 | effect 1; guarantee G8; checks `volume_existe`, `armazenamento` |
| FR-003 | effect 2; check `descricao` |
| FR-004 | precondition P2 and P5 (the creator becomes owner); check `dono` |
| FR-005, FR-006 | effects 3 and 4; check `acesso_direto` |
| FR-007 | effect 4; guarantee G6; rows `revogado` |
| FR-008 | check `acesso_herdado` |
| FR-009, FR-010 | guarantees G1, G4, G5 |
| FR-011 | guarantees G2, G3 |
| FR-012 | preconditions P1 to P5 |
| FR-013 | verification script |
| FR-014 | combined environment check |
| FR-015 | documentation task (see plan) |
