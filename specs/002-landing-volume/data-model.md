# Data Model: Landing Volume in Bronze

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-11

This feature creates no tables and stores no rows. Its "data" is catalog metadata: one
volume, its owner, its description and its grants.

## Entities

### Schema `workspace.bronze` (existing, read only)

| Attribute | Required value | Source |
|---|---|---|
| Exists | yes | created by feature 001 |
| Owner | `arthur.luz@dataslight.com.br` | feature 001 |

The feature requires the schema and never creates or alters it.

### Volume `workspace.bronze.landing` (created by this feature)

| Attribute | Rule | Requirement |
|---|---|---|
| Full name | `workspace.bronze.landing` | FR-001 |
| Type | `MANAGED` | FR-002 |
| Path | `/Volumes/workspace/bronze/landing` | follows from the name |
| Owner | `arthur.luz@dataslight.com.br` | FR-004 |
| Description | `Landing zone: arquivos de origem como chegaram, uma pasta por origem.` | FR-003 |
| Contents | none at creation; never removed by this feature | FR-010 |

### Source folder (not created by this feature)

Folders inside the volume, one per source, created by the data generators on first write:
`stream/`, `files/`, `database/`, plus the generator's working folder
`_checkpoint_stream/`. They are listed here only to state that the setup must leave them
untouched.

### Identity and access grant

As in [feature 001](../001-medallion-schemas/data-model.md). The authorized principal is
`arthur.luz@dataslight.com.br`. A grant on the volume is `direct` (given on the volume) or
`inherited` (given on the schema or the catalog).

## Rules

| # | Rule | Requirement |
|---|---|---|
| R1 | Exactly one volume is in scope: `workspace.bronze.landing`. No schema, table or other volume is created, changed or removed. | FR-001, FR-011 |
| R2 | The volume has exactly one direct grant set: `ALL PRIVILEGES` to the authorized principal. | FR-005, FR-006 |
| R3 | A direct grant to any other grantee is invalid and is revoked by the setup. | FR-007 |
| R4 | An inherited grant is not changed; it is reported with its grantee and privilege. | FR-008 |
| R5 | The setup runs only as the authorized principal, and only when `bronze` exists and is owned by that principal. | FR-012 |
| R6 | A volume named `landing` owned by someone else, or a table or view with that name, blocks the setup. | Edge cases |
| R7 | A volume whose type is not `MANAGED` is reported as a failure and left as it is. | Edge case |
| R8 | Files and folders in the volume are never listed for deletion, moved or removed. | FR-010 |

## States of the volume

```text
            setup (creates, sets description and grant)
 absent ─────────────────────────────────────────────────▶ compliant
                                                             │   ▲
                         someone adds a grant or edits       │   │ setup (revokes,
                         the description                     ▼   │ re-applies)
                                                           drifted

 foreign (exists, different owner) ──── setup ───▶ blocked, no change, error reported
 external (exists, not MANAGED) ─────── setup ───▶ grants applied, storage reported as FAIL
```

- **absent**: no volume named `landing` in `bronze`.
- **compliant**: exists, `MANAGED`, owned by the authorized principal, description set,
  R2 holds.
- **drifted**: owned correctly, with extra direct grants or a changed description. The
  setup returns it to compliant without touching its files.
- **foreign**: exists with another owner. The setup refuses to act.
- **external**: exists and is owned correctly, but its storage is not managed by the
  platform. The setup applies the access rule and reports the storage; it does not convert
  or drop the volume.

The setup has no transition that removes the volume or anything inside it.

## Verification report (output shape)

Same five columns as step 1; values of `ordem` start at 110. Defined in
[contracts/setup-and-verify.md](contracts/setup-and-verify.md).

| Check | Rows | Passes when |
|---|---|---|
| Target | 1 | always informational: user, catalog, metastore |
| Prerequisite | 1 | `bronze` exists and is owned by the authorized principal |
| Volume exists | 1 | the volume exists |
| Owner | 1 | the owner is the authorized principal |
| Storage | 1 | the type is `MANAGED` |
| Description | 1 | the description matches the table above |
| Direct access | 1 | the only grantee is the authorized principal |
| Inherited access | 0 or more | informational, or a failure if it gives access to files |

A compliant environment shows 6 `PASS` rows for this step.
