# Feature Specification: Landing Volume in Bronze

**Feature Branch**: `002-landing-volume`

**Created**: 2026-10-11

**Status**: Draft

**Input**: User description: "next we need to create a volume called landing under bronze schema."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create the landing volume (Priority: P1)

As the project owner, I want a storage volume named `landing` to exist in the `bronze`
schema of the `workspace` catalog, so that source files have a place to arrive before the
pipeline reads them.

**Why this priority**: it is the second step of the project and blocks the ones after it.
The data generators write their files into this volume and the bronze layer of the pipeline
reads from it. Without the volume neither can run.

**Independent Test**: run the setup against an environment where the volume does not
exist, then list the volumes of the `bronze` schema and confirm that `landing` is present,
empty, and reachable at the path the project uses for it.

**Acceptance Scenarios**:

1. **Given** the `bronze` schema exists and has no volume named `landing`, **When** the
   setup is run, **Then** a volume named `landing` exists in `workspace.bronze` and
   contains no files.
2. **Given** the volume was just created, **When** the owner inspects it, **Then** it
   states that it is the landing zone for source files, one folder per source.
3. **Given** the volume exists, **When** the owner writes a file to it and reads the file
   back through the volume's path, **Then** both operations succeed and the content
   matches.
4. **Given** the setup has finished, **When** the owner lists the contents of the three
   schemas, **Then** nothing other than the `landing` volume was created, changed or
   removed.

---

### User Story 2 - Keep the volume restricted to the project owner (Priority: P2)

As the project owner, I want `arthur.luz@dataslight.com.br` to be the only identity that
can see, read or write the landing volume, so that the access rule already applied to the
three schemas also holds for the files inside them.

**Why this priority**: the volume is usable without an explicit rule, because access to it
already depends on access to the `bronze` schema. Making the rule explicit and verifiable
comes second, and must be in place before any data lands.

**Independent Test**: after the setup, list who holds access to the volume and confirm that
the only identity is `arthur.luz@dataslight.com.br`, and that the same identity owns it.

**Acceptance Scenarios**:

1. **Given** the volume exists, **When** the access held on it is listed, **Then**
   `arthur.luz@dataslight.com.br` is the owner and the only identity with access granted on
   the volume.
2. **Given** an identity other than `arthur.luz@dataslight.com.br` exists in the
   environment, **When** that identity tries to list, read or write files in the volume,
   **Then** the attempt is refused.
3. **Given** access to the volume could be inherited from the `bronze` schema or from the
   catalog, **When** the setup is run, **Then** it reports every identity that reaches the
   volume that way, naming the identity and the access it holds.

---

### User Story 3 - Run the setup again safely (Priority: P3)

As the project owner, I want to be able to run the setup more than once, so that I can
rebuild the environment between presentations without errors and without losing the files
already in the volume.

**Why this priority**: generated source files take time to produce, so a setup that
recreated the volume on each run would destroy them. The first run already delivers the
value; safe re-runs protect it.

**Independent Test**: run the setup, write a file to the volume, run the setup again, and
confirm that the second run reports success and the file is still there with the same
content.

**Acceptance Scenarios**:

1. **Given** the volume already exists with the correct access, **When** the setup is run
   again, **Then** it completes without error and changes nothing.
2. **Given** the volume contains files, **When** the setup is run again, **Then** every
   file and folder is preserved unchanged.
3. **Given** an extra identity was granted access to the volume after the first run,
   **When** the setup is run again, **Then** that access is removed, the removal is
   reported, and the owner is again the only identity with access.
4. **Given** the volume was removed, **When** the setup is run again, **Then** the volume
   is created again, empty, and no schema is changed.

---

### Edge Cases

- The `bronze` schema does not exist: the setup must stop with a message saying that the
  schemas step has to run first, and must not create the schema itself.
- The `bronze` schema exists but is not owned by `arthur.luz@dataslight.com.br`: the setup
  must stop and report it, since the access rule of the previous step does not hold.
- The identity running the setup is not `arthur.luz@dataslight.com.br`: the setup must
  refuse to run, so that the volume is never left owned by whoever ran it.
- A volume named `landing` already exists and is owned by someone else: the setup must
  report it and must not take ownership or change its access silently.
- An object of another kind named `landing` (a table, for example) already exists in
  `bronze`: the setup must stop with a clear message and must not remove the object.
- The volume already exists but its files are stored in a location chosen by someone else
  instead of being managed by the platform: the setup must report this and leave it as it
  is.
- The setup is run against the wrong environment: it must make the target environment
  visible before making changes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The setup MUST create a volume named exactly `landing` in the schema
  `bronze` of the catalog `workspace`.
- **FR-002**: The volume's storage MUST be managed by the platform, so that no storage
  location has to be provided or configured.
- **FR-003**: The volume MUST carry a description stating that it is the landing zone for
  source files, with one folder per source.
- **FR-004**: The volume MUST be owned by `arthur.luz@dataslight.com.br`.
- **FR-005**: `arthur.luz@dataslight.com.br` MUST be able to list, read, write and remove
  files and folders in the volume.
- **FR-006**: No user, group or automated identity other than
  `arthur.luz@dataslight.com.br` MUST hold access granted on the volume.
- **FR-007**: The setup MUST remove from the volume any access held by another identity,
  and MUST report each access it removed.
- **FR-008**: The setup MUST report any identity that can reach the volume through access
  inherited from the `bronze` schema or from the catalog, naming the identity and the
  access it holds.
- **FR-009**: The setup MUST be repeatable: running it when the volume already exists MUST
  succeed, MUST preserve every file and folder in it, and MUST restore the access rule.
- **FR-010**: The setup MUST NOT remove the volume or any file or folder inside it.
- **FR-011**: The setup MUST NOT create, change or remove any schema, any other volume, or
  any table.
- **FR-012**: The setup MUST refuse to run, changing nothing, when the `bronze` schema does
  not exist, when it is not owned by `arthur.luz@dataslight.com.br`, or when the identity
  running the setup is someone else. Each refusal MUST name its reason.
- **FR-013**: The owner MUST be able to verify the outcome on demand: whether the volume
  exists, who owns it, how its storage is managed, and which identities hold access to it.
- **FR-014**: The verification of this step MUST be available together with the
  verification of the schemas step, so that one check tells the owner whether the
  environment is ready up to this point.
- **FR-015**: The steps to run and verify the setup MUST be recorded in the project
  documentation, replacing the manual instruction currently given there for the volume.

### Key Entities

- **Schema `bronze`**: the existing container, created by the previous step, that will hold
  the volume. This feature reads it and does not change it.
- **Volume `landing`**: a named storage area for files inside the `bronze` schema. It has
  an owner, a description, a set of access grants, and a path through which files are
  written and read. It is the single entry point for source files in the project.
- **Source folder**: a folder inside the volume that receives the files of one source. The
  project uses one per source. This feature does not create them.
- **Identity**: a user, group or automated account known to the environment. Exactly one is
  authorized here: `arthur.luz@dataslight.com.br`.
- **Access grant**: the record that an identity may perform an operation on the volume. It
  can be given on the volume itself or inherited from the schema or the catalog.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After one run of the setup on an environment without it, exactly 1 volume
  named `landing` exists in the `bronze` schema, with 0 files.
- **SC-002**: The list of identities with access granted on the volume contains exactly 1
  entry: `arthur.luz@dataslight.com.br`.
- **SC-003**: 100% of attempts by any other identity to list, read or write files in the
  volume are refused.
- **SC-004**: A file written to the volume by the owner can be read back with identical
  content in 100% of attempts.
- **SC-005**: Running the setup a second time removes 0 files, changes 0 schemas and
  finishes without error.
- **SC-006**: The owner can go from an environment with only the schemas to a verified
  environment with the landing volume in under 2 minutes, without typing the volume
  definition by hand.
- **SC-007**: The next project step, which generates source files into the volume, can
  start without any further change to the volume or to its access.

## Assumptions

- "Under bronze schema" refers to `workspace.bronze` in the Databricks Free Edition
  environment of the project, created by feature 001 and owned by
  `arthur.luz@dataslight.com.br`.
- The access rule of feature 001 extends to this volume: only
  `arthur.luz@dataslight.com.br` has access. The request does not restate it, but a
  landing zone open to others would contradict the rule already applied to the schema that
  contains it.
- The volume's files are stored and managed by the platform. An externally located volume
  is out of scope; the Free Edition environment does not need one.
- The folders inside the volume (one per source, plus the working folder the stream
  generator uses) are out of scope. They are created by the data generators when they first
  write, as they are today.
- Generating data, the calendar table and the pipeline are out of scope. They are later
  steps of the project.
- Catalog-level and schema-level access are out of scope: this feature reports what is
  inherited and does not change it. Capabilities that the platform gives to environment
  administrators and to the catalog owner by design are reported, not treated as a failure.
- The environment has a single user today, so refusal for other identities is demonstrated
  by the absence of grants. A direct attempt is made only if a second identity exists.
- The setup is auxiliary code run by a person on demand. It follows the same conventions as
  the schemas step and lives beside it. Scheduling it is out of scope.
- No real or personal data is placed in the volume; the project uses synthetic data only.
