# Feature Specification: Medallion Schemas with Restricted Access

**Feature Branch**: `001-medallion-schemas`

**Created**: 2026-10-10

**Status**: Draft

**Input**: User description: "the first step of the project is create 3 schemas - bronze, silver and gold under workspace workspace name on databricks free env. Just arthur.luz@dataslight.com.br can have access to all schemas."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create the three layer schemas (Priority: P1)

As the project owner, I want the `bronze`, `silver` and `gold` schemas to exist in the
`workspace` catalog of the Databricks Free Edition environment, so that every later step of
the project (landing data, pipeline, analytics model) has a place to publish its datasets.

**Why this priority**: nothing else in the project can run without these schemas. The
pipeline publishes to them by name, and the data generators write under `bronze`. This is
the foundation of the medallion architecture the constitution requires.

**Independent Test**: run the setup against an environment where the schemas do not exist,
then list the schemas of the `workspace` catalog and confirm that `bronze`, `silver` and
`gold` are present and empty.

**Acceptance Scenarios**:

1. **Given** the `workspace` catalog has no `bronze`, `silver` or `gold` schema, **When**
   the setup is run, **Then** all three schemas exist in the `workspace` catalog and contain
   no objects.
2. **Given** the three schemas were just created, **When** the owner inspects each one,
   **Then** each schema states which layer it is (bronze, silver or gold) and what that
   layer holds.
3. **Given** the setup has finished, **When** the owner lists the schemas of the catalog,
   **Then** no schema other than the three requested was created, changed or removed.

---

### User Story 2 - Restrict access to the project owner (Priority: P2)

As the project owner, I want `arthur.luz@dataslight.com.br` to be the only identity that
can see or use the three schemas, so that the demo environment cannot be read or changed
by anyone else.

**Why this priority**: the schemas are usable without it, so it comes after creation, but
the access rule is an explicit requirement and must be in place before any data lands.

**Independent Test**: after the setup, list who holds access to each of the three schemas
and confirm that the only identity is `arthur.luz@dataslight.com.br`; then confirm that
this identity can create an object in each schema.

**Acceptance Scenarios**:

1. **Given** the three schemas exist, **When** the access held on each schema is listed,
   **Then** `arthur.luz@dataslight.com.br` is the owner and the only identity with access
   granted on the schema.
2. **Given** the access rule is in place, **When** `arthur.luz@dataslight.com.br` creates,
   reads, changes and removes an object in each of the three schemas, **Then** every
   operation succeeds.
3. **Given** an identity other than `arthur.luz@dataslight.com.br` exists in the
   environment, **When** that identity tries to list, read or create objects in any of the
   three schemas, **Then** the attempt is refused.
4. **Given** access to the catalog was previously granted to a group or to all users,
   **When** the setup is run, **Then** that access does not extend to the three schemas,
   or the setup reports that it does and names the identity that still has access.

---

### User Story 3 - Run the setup again safely (Priority: P3)

As the project owner, I want to be able to run the setup more than once, so that I can
rebuild the environment after a clean-up, or re-apply it after a mistake, without errors
and without losing data.

**Why this priority**: the demo is torn down and rebuilt between presentations. A setup
that fails or destroys data on the second run would make that unsafe, but the first run
already delivers the value.

**Independent Test**: run the setup twice in a row, with an object created in one schema
between the two runs, and confirm that the second run reports success, the object is still
there, and the access rule is unchanged.

**Acceptance Scenarios**:

1. **Given** the three schemas already exist with the correct access, **When** the setup is
   run again, **Then** it completes without error and changes nothing.
2. **Given** a schema contains objects, **When** the setup is run again, **Then** every
   object and its data are preserved.
3. **Given** one of the three schemas was removed, **When** the setup is run again,
   **Then** only the missing schema is created and the other two are left untouched.
4. **Given** an extra identity was granted access to a schema after the first run,
   **When** the setup is run again, **Then** that access is removed and the owner is again
   the only identity with access.

---

### Edge Cases

- The identity running the setup is not `arthur.luz@dataslight.com.br`: the setup must
  not leave the schemas owned by, or accessible to, the identity that ran it.
- The identity running the setup lacks permission to create schemas in the catalog: the
  setup must stop with a message that names the missing permission, and must not leave
  some schemas created and others not without saying which.
- A schema with one of the three names already exists and is owned by someone else: the
  setup must report it and must not take ownership or change its access silently.
- Access inherited from the catalog reaches the schemas: an identity granted access at the
  catalog level would see the schemas even with no grant on them. The setup must detect
  and report this.
- The setup is run against the wrong environment: it must make the target environment and
  catalog visible before making changes, so that a mistake is noticed.
- The `workspace` catalog does not exist in the target environment: the setup must stop
  with a clear message and must not create a catalog.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The setup MUST create three schemas named exactly `bronze`, `silver` and
  `gold` in the catalog named `workspace`.
- **FR-002**: The setup MUST target the Databricks Free Edition environment of the project
  and MUST NOT create or alter schemas in any other catalog or environment.
- **FR-003**: Each schema MUST carry a description stating its layer and the kind of data it
  holds, consistent with the layer definitions in the project constitution.
- **FR-004**: Each of the three schemas MUST be owned by `arthur.luz@dataslight.com.br`.
- **FR-005**: `arthur.luz@dataslight.com.br` MUST be able to perform every operation on
  each of the three schemas and on the objects created in them: create, read, change and
  remove.
- **FR-006**: No user, group or automated identity other than
  `arthur.luz@dataslight.com.br` MUST hold access granted on any of the three schemas.
- **FR-007**: The setup MUST remove from the three schemas any access held by another
  identity, and MUST report each access it removed.
- **FR-008**: The setup MUST report any identity that can reach the three schemas through
  access inherited from the catalog, naming the identity and the access it holds.
- **FR-009**: The setup MUST be repeatable: running it when the schemas already exist MUST
  succeed, MUST preserve every object and its data, and MUST restore the access rule.
- **FR-010**: The setup MUST NOT remove a schema or any object inside a schema.
- **FR-011**: The setup MUST NOT create, change or remove any schema other than `bronze`,
  `silver` and `gold`.
- **FR-012**: When the setup cannot complete, it MUST state which schemas were created,
  which were not, and why.
- **FR-013**: The owner MUST be able to verify the outcome on demand: which of the three
  schemas exist, who owns each one, and which identities hold access to each one.
- **FR-014**: The steps to run and verify the setup MUST be recorded in the project
  documentation, replacing the manual instructions currently given there.

### Key Entities

- **Catalog**: the top-level container named `workspace` that already exists in the
  environment. It holds the schemas. This feature reads it and does not change it.
- **Schema**: a named container for datasets inside the catalog. Three are in scope, one
  per medallion layer: `bronze` (source data as it arrived), `silver` (validated and
  conformed data) and `gold` (the analytics model). Each has an owner, a description and a
  set of access grants.
- **Identity**: a user, group or automated account known to the environment. Exactly one
  is authorized here: `arthur.luz@dataslight.com.br`.
- **Access grant**: the record that an identity may perform an operation on a schema. It
  can be given on the schema itself or inherited from the catalog.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After one run of the setup on an environment without them, all 3 schemas
  exist in the `workspace` catalog.
- **SC-002**: For each of the 3 schemas, the list of identities with access contains
  exactly 1 entry: `arthur.luz@dataslight.com.br`.
- **SC-003**: 100% of attempts by any other identity to list, read or create objects in
  the three schemas are refused.
- **SC-004**: Running the setup a second time changes 0 schemas, removes 0 objects and
  finishes without error.
- **SC-005**: The owner can go from an environment without the schemas to a verified,
  ready environment in under 5 minutes, without typing the schema definitions by hand.
- **SC-006**: The next project step, which places data in `bronze` and publishes datasets
  to all three schemas, can start without any further change to schemas or access.

## Assumptions

- "workspace workspace name" in the request refers to the catalog named `workspace`,
  the default catalog of the Databricks Free Edition environment, as fixed by the project
  constitution.
- The target environment is the Free Edition workspace already used by the project, where
  `arthur.luz@dataslight.com.br` is the signed-in user and has permission to create
  schemas in the `workspace` catalog.
- "Access to all schemas" means full control: ownership plus every operation on the
  schemas and on the objects inside them.
- "Just arthur.luz@dataslight.com.br" excludes every other user, group and automated
  identity from access granted on the schemas. Capabilities that the platform gives to
  environment administrators and to the owner of the catalog by design cannot be removed
  at schema level; they are reported, not treated as a failure.
- The `bronze`, `silver` and `gold` schemas do not currently exist in the environment;
  they were dropped on 2026-10-10. The setup still handles the case where they do.
- The landing area for source files inside `bronze`, the data generators, the calendar
  table and the pipeline itself are out of scope. They are later steps of the project.
- Catalog-level access is out of scope: this feature reports it and does not change it,
  because the catalog also holds schemas that do not belong to this project.
- The setup is run by a person on demand. Scheduling it or running it automatically is out
  of scope.
- The setup is environment preparation, not pipeline code, so the SQL-only pipeline
  principle of the constitution governs it only in spirit; the naming and catalog
  constraints of the constitution apply in full.
