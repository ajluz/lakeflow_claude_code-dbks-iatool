# Contract: Setup and Verification Scripts

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-10

The feature exposes two scripts to the project owner. This document fixes what each one
accepts, does, returns and refuses, so that they can be written and tested against it.

## Common interface

| Aspect | Contract |
|---|---|
| Form | each script is one SQL statement, runnable on a Databricks SQL warehouse |
| Invocation | `databricks experimental aitools tools query <file> --profile <profile>`, or pasted into the SQL editor |
| Profile | always chosen and passed by the caller; never stored in the script |
| Parameters | none; the catalog, the three schema names and the authorized principal are constants at the top of each script |
| Result | one result set, the verification report defined below |
| Exit | CLI exit code is non-zero when the statement raises an error |

## `setup/01_schemas.sql`

**Purpose**: bring the three schemas to the compliant state defined in
[../data-model.md](../data-model.md).

### Preconditions (checked before any change)

| # | Condition | On failure: error message contains |
|---|---|---|
| P1 | the catalog `workspace` exists | `catalog workspace not found` |
| P2 | `current_user()` is the authorized principal | `must be run as arthur.luz@dataslight.com.br` and the actual user |
| P3 | none of the three schemas exists with a different owner | `schema <name> is owned by <owner>` for each offending schema |

When any precondition fails the script raises an error and has changed nothing.

### Effects, per schema, in the order `bronze`, `silver`, `gold`

1. Create the schema if it does not exist.
2. Set the schema description to the text in the data model.
3. Grant `ALL PRIVILEGES` on the schema to the authorized principal.
4. Revoke every privilege granted directly on the schema to any other grantee.

### Guarantees

| # | Guarantee | Requirement |
|---|---|---|
| G1 | Never drops a schema or an object inside one. | FR-010 |
| G2 | Never creates, alters or drops any other schema, or the catalog. | FR-002, FR-011 |
| G3 | Never changes a grant on the catalog. | Assumptions |
| G4 | Running it on compliant schemas changes nothing and succeeds. | FR-009 |
| G5 | Running it on drifted schemas restores compliance and keeps all contents. | FR-009 |
| G6 | Reports each privilege it revoked: schema, grantee, privilege. | FR-007 |
| G7 | Ends by returning the verification report. | FR-013 |

### If it stops midway

An unexpected error after the preconditions (for example a lost connection) can leave some
schemas created and others not. Every step is repeatable, so the recovery is to run the
script again; the verification script shows the current state at any time (FR-012).

## `setup/01_schemas_verify.sql`

**Purpose**: report the current state on demand. Read-only: it creates, alters, grants and
revokes nothing, and is safe to run in any state, including before the setup.

### Guarantees

| # | Guarantee |
|---|---|
| V1 | Makes no change to the environment. |
| V2 | Succeeds whether or not the schemas exist; a missing schema is a `FAIL` row, not an error. |
| V3 | Returns the verification report. |

## Verification report

One result set, ordered by `ordem`.

| Column | Type | Meaning |
|---|---|---|
| `ordem` | INT | display order |
| `verificacao` | STRING | check name, from the list below |
| `objeto` | STRING | what was checked: `workspace`, or `workspace.<schema>` |
| `resultado` | STRING | `PASS`, `FAIL` or `INFO` |
| `detalhe` | STRING | the observed value, and for `FAIL` what was expected |

| `verificacao` | Rows | `PASS` when |
|---|---|---|
| `alvo` | 1 | always `INFO`: current user, catalog, metastore |
| `schema_existe` | 3 | the schema exists |
| `dono` | 3 | the owner is the authorized principal |
| `descricao` | 3 | the description matches the data model |
| `acesso_direto` | 3 | the authorized principal is the only grantee with a direct grant |
| `acesso_herdado` | 0 or more | `INFO` for a grant that gives no access to schema contents (such as `USE_CATALOG` alone); `FAIL` for one that does |
| `dono_catalogo` | 1 | always `INFO`: the catalog owner, whose members can manage the schemas by platform design |
| `revogado` | 0 or more | setup script only, always `INFO`: a privilege removed in this run |

**Overall result**: the environment is compliant when the report has no `FAIL` row. On a
clean first run it has 12 `PASS` rows (4 checks × 3 schemas).

## Mapping to the specification

| Spec item | Covered by |
|---|---|
| FR-001, FR-002, FR-011 | effects 1; guarantee G2; precondition P1 |
| FR-003 | effect 2; check `descricao` |
| FR-004 | precondition P2 (the creator becomes owner); check `dono` |
| FR-005, FR-006 | effects 3 and 4; check `acesso_direto` |
| FR-007 | effect 4; guarantee G6; rows `revogado` |
| FR-008 | checks `acesso_herdado` and `dono_catalogo` |
| FR-009, FR-010 | guarantees G1, G4, G5 |
| FR-012 | preconditions; "If it stops midway" |
| FR-013 | verification script |
| FR-014 | documentation task (see plan) |
