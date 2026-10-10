# Research: Medallion Schemas with Restricted Access

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-10

Findings marked *observed* were read from the target environment on 2026-10-10 with
read-only queries (profile `databricks-free`, host `dbc-7e0f02e0-ff06`). Nothing was
changed there.

## State of the target environment (observed)

| Fact | Value |
|---|---|
| Catalog `workspace` | exists, managed, owned by the group `_workspace_admins_workspace_2398601852378223` |
| Schemas in the catalog | `default`, `information_schema` only; `bronze`, `silver`, `gold` do not exist |
| Grants on the catalog | `USE_CATALOG` to `_workspace_users_workspace_2398601852378223`, nothing else |
| Users in the workspace | one: `arthur.luz@dataslight.com.br`, member of `admins` |
| SQL warehouse | serverless, DBSQL `2026.38`, detected automatically by the CLI |
| SQL scripting | works: `BEGIN ... END`, `DECLARE`, `FOR ... DO`, `IF`, `EXECUTE IMMEDIATE`, `SIGNAL` all ran |
| `workspace.information_schema.schema_privileges` | has `grantee`, `schema_name`, `privilege_type`, `inherited_from` |

## Decision 1: how the schemas are created

**Decision**: one idempotent SQL script, `setup/01_schemas.sql`, written as a single SQL
scripting compound statement and run on the SQL warehouse.

**Rationale**:
- It is plain SQL, which keeps the project in one language as Principle II intends, even
  though that principle formally binds pipeline code only.
- A compound statement is one statement, so it runs unchanged from the CLI, the SQL editor,
  or a notebook cell.
- SQL scripting gives the control flow the spec needs: check before changing (FR-012),
  loop over existing grants to revoke them (FR-007), and stop with a named error (edge
  cases). Plain `CREATE SCHEMA IF NOT EXISTS` statements cannot do any of that.
- `CREATE SCHEMA IF NOT EXISTS` plus re-applied grants is naturally repeatable (FR-009) and
  never drops anything (FR-010).

**Alternatives considered**:
- *Bundle resources (`resources.schemas` with `grants` in `databricks.yml`)*. Rejected. The
  only target is in development mode, which prefixes resource names, so the schemas would
  not be named exactly `bronze`, `silver`, `gold` (FR-001). Removing a schema from the
  bundle, or running `bundle destroy`, drops it and its data (FR-010). A bundle also cannot
  report access inherited from the catalog (FR-008).
- *Python with the Databricks SDK or a notebook*. Rejected. It adds a second language and a
  local environment dependency for something SQL does directly.
- *Manual statements in the documentation* (the current state of
  `doc/getting-started.md`). Rejected: no access rule, no verification, not repeatable in
  the sense of restoring access.

## Decision 2: how "only one identity has access" is enforced

**Decision**: for each schema the script (a) makes `arthur.luz@dataslight.com.br` the
owner, (b) grants that identity `ALL PRIVILEGES` on the schema, and (c) revokes every
privilege granted directly on the schema to any other grantee, found in
`workspace.information_schema.schema_privileges` where `inherited_from = 'NONE'`.

**Rationale**:
- Ownership already implies full control, but an owner with no grant shows an empty grant
  list. The explicit grant makes the list read "exactly one identity", which is what
  SC-002 measures.
- Reading the grants from the information schema, instead of hardcoding who to revoke,
  makes the script correct for grants nobody anticipated (User Story 3, scenario 4).
- A new schema in Unity Catalog starts with no grants, so on a first run step (c) finds
  nothing; it matters on later runs.

**Alternatives considered**:
- *Rely on ownership alone*. Rejected: fails SC-002 as written and leaves later grants in
  place.
- *Revoke a fixed list of groups (`account users`, workspace users)*. Rejected: misses any
  other grantee.

## Decision 3: access inherited from the catalog

**Decision**: report it, do not change it. The verification output lists every row of
`schema_privileges` for the three schemas whose `inherited_from` is not `NONE`, and every
grant on the catalog itself, each with a note on whether it gives access to schema
contents.

**Rationale**:
- The spec puts catalog-level access out of scope because the catalog also holds schemas
  that are not part of this project (`default`).
- *Observed*: the only catalog grant is `USE_CATALOG` to the workspace users group.
  `USE CATALOG` alone does not allow listing, reading or creating anything in a schema;
  that also requires `USE SCHEMA` and an object privilege, none of which are granted. So
  today nothing reaches the schemas through inheritance.
- *Observed*: the catalog is owned by the workspace admins group. Members of that group can
  manage every object in the catalog by design, and this cannot be revoked at schema
  level. The only member is `arthur.luz@dataslight.com.br`, so today this adds no second
  identity. The verification output states this dependency so that adding an admin later
  is a visible change, not a silent one.

**Alternatives considered**:
- *Revoke `USE_CATALOG` from the workspace users group*. Rejected: out of scope, affects
  the `default` schema, and changes nothing about schema access.
- *Change the catalog owner to the single user*. Rejected: out of scope and alters a
  platform default of the Free Edition workspace.

## Decision 4: who may run the setup, and against what

**Decision**: the script starts with pre-flight checks and makes no change unless all pass:

1. the catalog `workspace` exists;
2. `current_user()` is `arthur.luz@dataslight.com.br`;
3. no schema named `bronze`, `silver` or `gold` exists with a different owner.

Each failure stops the run with a message naming the check. The target is chosen by the
caller through an explicit `--profile`; the script's first output row shows the user,
catalog and metastore it ran against.

**Rationale**:
- Refusing to run as anyone else is the simplest way to guarantee the schemas are never
  left owned by, or accessible to, the identity that ran the setup.
- Checking all three schemas before creating any gives all-or-nothing behavior for the
  foreseeable failures, which satisfies FR-012 without partial-state reporting logic.
- The constitution forbids selecting a CLI profile on the user's behalf, so the profile
  stays a caller decision and is never written into the script.

**Alternatives considered**:
- *Let any identity run it and transfer ownership afterwards*. Rejected: the runner would
  need extra privileges, and a failure between create and transfer would leave the wrong
  owner.
- *Take over a schema owned by someone else*. Rejected by the spec's edge case.

## Decision 5: verification

**Decision**: a second, read-only script, `setup/01_schemas_verify.sql`, returns one row
per check with a `PASS` / `FAIL` / `INFO` result. It can be run at any time (FR-013). The
setup script ends by returning the same report.

**Rationale**: verification must be available on demand, independently of running the
setup. Keeping it read-only makes it safe to run in any state.

**Limit that cannot be tested today**: SC-003 (attempts by another identity are refused)
needs a second identity, and the workspace has exactly one user. It is verified by proof
instead of by attempt: no grant exists for any other grantee, directly or by inheritance.
If a second user is ever added, the quickstart describes the direct test.

**Alternatives considered**:
- *A test framework (`pytest` with Databricks Connect)*. Rejected: the check is three
  metadata queries; the dependency is not justified.

## Decision 6: schema descriptions

**Decision**: each schema gets a `COMMENT` in Portuguese stating its layer and contents,
taken from the layer definitions of Principle I. The comment is re-applied on every run.

**Rationale**: object names in this project are in Portuguese and the catalog is what the
talk's audience sees. Re-applying keeps the description correct if someone edits it.

**Alternatives considered**: English comments, matching the documentation. Either works;
this is a one-line change if the owner prefers it.

## Decision 7: where the files live

**Decision**: a new top-level folder `setup/`, with files prefixed by step number
(`01_schemas.sql`, `01_schemas_verify.sql`).

**Rationale**: environment preparation is neither pipeline source (`code_tips/`) nor
exploration (`explorations/`). Putting it in the pipeline folder would make the pipeline
try to run it. Later steps (landing volume, calendar table) have the same nature and can
follow as `02_`, `03_`.

**Constitution impact**: the "Repository layout" constraint lists `code_tips/`,
`explorations/` and `doc/` and does not mention `setup/`. This is recorded in the plan's
Complexity Tracking, with a recommended amendment.

## Open questions

None. All items in Technical Context are resolved.
