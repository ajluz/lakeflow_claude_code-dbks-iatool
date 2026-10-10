# Data Model: Medallion Schemas with Restricted Access

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-10

This feature creates no tables and stores no rows. Its "data" is catalog metadata: three
schemas, their owner, their description and their grants.

## Entities

### Catalog (existing, read only)

| Attribute | Value | Source |
|---|---|---|
| Name | `workspace` | constitution, Platform and Technology Constraints |
| Owner | workspace admins group | platform default, not changed |
| Grants | `USE_CATALOG` to the workspace users group | platform default, not changed |

The feature requires the catalog to exist and never creates or alters it.

### Schema (created by this feature)

Three instances, identical in shape.

| Attribute | Rule |
|---|---|
| Full name | `workspace.<layer>`, where `<layer>` is one of the names below |
| Owner | `arthur.luz@dataslight.com.br` (FR-004) |
| Description | states the layer and what it holds (FR-003); re-applied on each run |
| Contents | none at creation; never removed by this feature (FR-010) |

| Name | Layer | Holds | Description (Portuguese) |
|---|---|---|---|
| `bronze` | Bronze | source data as it arrived | Camada bronze: dados brutos, exatamente como chegaram da origem. |
| `silver` | Silver | validated, typed, conformed data | Camada silver: dados validados, tipados e conformados. |
| `gold` | Gold | the analytics model | Camada gold: modelo analítico (dimensões, fatos e tabelas desnormalizadas). |

### Identity

| Attribute | Value |
|---|---|
| Authorized principal | `arthur.luz@dataslight.com.br` |
| Role | owner of the three schemas; the only identity allowed to run the setup |

Every other user, group or service principal is unauthorized for the purposes of this
feature.

### Access grant

| Attribute | Meaning |
|---|---|
| Schema | which of the three schemas the grant applies to |
| Grantee | the identity holding the privilege |
| Privilege | the operation allowed |
| Origin | `direct` (granted on the schema) or `inherited` (granted on the catalog) |

## Rules

| # | Rule | Requirement |
|---|---|---|
| R1 | Exactly three schemas are in scope: `bronze`, `silver`, `gold`. No other schema is created, changed or removed. | FR-001, FR-011 |
| R2 | Each schema has exactly one direct grant set: `ALL PRIVILEGES` to the authorized principal. | FR-005, FR-006 |
| R3 | A direct grant to any other grantee is invalid and is revoked by the setup. | FR-007 |
| R4 | An inherited grant is not changed; it is reported with its grantee and privilege. | FR-008 |
| R5 | A schema that already exists with a different owner blocks the whole setup. | Edge case |
| R6 | The setup runs only as the authorized principal. | Edge case |

## States of a schema

```text
            setup (creates, sets description and grant)
 absent ─────────────────────────────────────────────────▶ compliant
                                                             │   ▲
                         someone adds a grant or edits       │   │ setup (revokes,
                         the description                     ▼   │ re-applies)
                                                           drifted

 foreign (exists, different owner) ──── setup ───▶ blocked, no change, error reported
```

- **absent**: the schema does not exist.
- **compliant**: exists, owned by the authorized principal, description set, R2 holds.
- **drifted**: exists and owned correctly, but has extra direct grants or a changed
  description. Running the setup returns it to compliant without touching its contents.
- **foreign**: exists with another owner. The setup refuses to act on any schema.

The setup has no transition that removes a schema or its contents.

## Verification report (output shape)

Both scripts return this report; the columns are defined in
[contracts/setup-and-verify.md](contracts/setup-and-verify.md).

| Check | One row per | Passes when |
|---|---|---|
| Target | run | always informational: user, catalog, metastore |
| Schema exists | schema | the schema exists |
| Owner | schema | the owner is the authorized principal |
| Description | schema | the description matches the table above |
| Direct access | schema | the only grantee is the authorized principal |
| Inherited access | inherited grant | informational, or a failure if it gives access to schema contents |
| Catalog ownership | run | informational: who owns the catalog |
