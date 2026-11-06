# Feature Specification: Gold Course Dimension (SCD Type 2)

**Feature Branch**: `012-gold-dim-curso`

**Created**: 2026-11-05

**Status**: Draft

**Input**: User description: "create a dim_curso with the follow fields: sk_curso, curso_uuid STRING, nome_curso STRING, nivel_curso STRING, valor_curso double, start_at TIMESTAMP, end_at TIMESTAMP. The dimension needs to be constructed as scd type 2."

## Clarifications

### Session 2026-11-05

- Q: The request names the history columns `start_at` and `end_at`, but SCD type 2 on a change feed always names them `__START_AT` and `__END_AT` and cannot rename them. How does the dimension get its validity columns? → A: Keep `__START_AT` and `__END_AT`, in one dimension fed by the change feed (owner).
- Q: The request asks for `valor_curso` as `double`, but the feed view and `silver.tb_curso` store it as `DECIMAL(9,2)`, and the constitution says both carry the same price type. Which type? → A: `DECIMAL(9,2)` (owner).
- Q: The request lists neither `origem` nor `data_carga`. Should the dimension include them? → A: Add `data_carga` only, as the other gold dimensions do; `origem` stays out (owner).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One dimension row per course version (Priority: P1)

As an analyst, I want `workspace.gold.dim_curso` to describe every course in the catalog,
with a surrogate key, a name, a level, a price and the period each version was valid, so
that sales and accesses can be sliced by course.

**Why this priority**: it is the course side of the star schema that `fato_venda` will
join, and the only place the course catalog's history is kept.

**Independent Test**: after a run on the initial catalog, `dim_curso` has one current row
per course, three in all, each with the values of its insert and a validity start equal
to the insert's change time.

**Acceptance Scenarios**:

1. **Given** the three inserts of the initial catalog, **When** the run completes,
   **Then** `dim_curso` has three course rows, one per `curso_uuid`, with `nome_curso`,
   `nivel_curso` and `valor_curso` as in the feed, `__START_AT` equal to the change time of
   the insert and an empty `__END_AT`.
2. **Given** a course row, **When** its columns are read, **Then** it carries none of the
   change-control columns (the change type and the change time), none of the bronze
   lineage columns and no record source, and its `data_carga` is filled.
3. **Given** the current rows (`__END_AT` empty), **When** they are compared with
   `silver.tb_curso`, **Then** they hold the same courses with the same name, level and
   price.
4. **Given** a run with no new change, **When** it completes, **Then** `dim_curso` is
   unchanged.

---

### User Story 2 - Updates keep the previous version (Priority: P1)

As an analyst, I want a course update to close the course's current version and open a
new one, so that a sale made before the update is still described by the price and name
in effect when it happened.

**Why this priority**: this is the "SCD type 2" behavior the request asks for, and the
talk demonstrates it on this table, next to the SCD type 1 `silver.tb_curso`.

**Independent Test**: at the live demo, after the generator delivers the update of
*Construindo um Data Lakehouse com SQL e DLT* to `147.00`, that course has two rows: the
old version at `247.00`, closed at the update's change time, and the new version at
`147.00`, open. Implementation does not run this test (Assumptions).

**Acceptance Scenarios**:

1. **Given** an update of a course, **When** the run completes, **Then** the course's
   previous version has `__END_AT` equal to the update's change time, and a new version
   holds the updated values, with `__START_AT` equal to the same change time and an empty
   `__END_AT`.
2. **Given** an update, **When** the versions of that course are read, **Then** each has
   its own surrogate key, and the previous version keeps the key it had before the update.
3. **Given** two changes to the same course delivered in one run, **When** the run
   completes, **Then** both become versions, in change-time order, and the current one
   holds the values of the latest change.

---

### User Story 3 - Deletions close the course without erasing it (Priority: P1)

As an analyst, I want a course deletion to close the course's current version instead of
removing it, so that past sales of a withdrawn course still find their course.

**Why this priority**: the generator's change feed ends with a deletion, and keeping the
deleted course is what distinguishes this dimension from `silver.tb_curso`.

**Independent Test**: at the live demo, after the generator delivers the deletion of
*Construindo um Data Lakehouse com SQL e DLT*, the course still has its rows, none of them
open; the other two courses are unchanged. Implementation does not run this test.

**Acceptance Scenarios**:

1. **Given** a deletion of a course, **When** the run completes, **Then** the course's
   current version has `__END_AT` equal to the deletion's change time, and no version of the
   course is open.
2. **Given** a deletion, **When** the dimension is read, **Then** every earlier version
   of the course is still there, with its key unchanged.
3. **Given** a deletion whose change time is earlier than the course's latest update,
   **When** the run completes, **Then** the newer version is not closed by it: changes
   are applied in change-time order, not in arrival order.

---

### User Story 4 - Explicit members for unknown and not-applicable courses (Priority: P1)

As an analyst, I want the dimension to contain an "unknown" course and a "not applicable"
course, so that a fact whose course is missing or does not apply still points to a row and
no fact row is lost in a join.

**Why this priority**: the constitution requires both members in every dimension
(Principle VII), and the facts' reconciliation rule depends on them (Principle I).

**Independent Test**: after a run, the dimension has exactly one "unknown" row and one
"not applicable" row, each with a fixed key that no course version can take, and both
always current.

**Acceptance Scenarios**:

1. **Given** the dimension, **When** it is read, **Then** it has one row labelled
   `Desconhecido` and one labelled `Não se aplica`, in every text attribute, with an empty
   price.
2. **Given** later updates, deletions or runs, **When** the members are read, **Then**
   their keys and values are unchanged and they are never closed.

---

### Edge Cases

- **The same course inserted again after a deletion.** A later insert with a later change
  time opens a new version; the closed versions stay.
- **Two changes with the same change time for one course.** The order between them is
  undefined. The generator writes each change in its own run, so this is not expected;
  planning states how a tie is resolved.
- **The initial catalog delivered again.** A second delivery of the same inserts, with the
  same change time, must not create duplicate versions.
- **A change with no effect on the values.** An update that repeats the current values
  still arrives as a change event; planning states whether it opens a version.
- **All three initial courses share one change time** (`2026-10-11 22:42:09.713` UTC on
  2026-11-05). Keys must still differ between courses.
- **A fact dated before a course's first version.** It finds no version in effect;
  resolving it is the fact's concern (out of scope), through the "unknown" member.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a gold dimension `workspace.gold.dim_curso`, fed
  incrementally from the course catalog's change feed.
- **FR-002**: The dimension MUST have exactly these columns:

  | Column | Type | Meaning |
  |---|---|---|
  | `sk_curso` | BIGINT | surrogate key, one per course version |
  | `curso_uuid` | STRING | the course identifier delivered by the source (business key) |
  | `nome_curso` | STRING | course name |
  | `nivel_curso` | STRING | course level |
  | `valor_curso` | DECIMAL(9,2) | course price, an exact two-decimal amount, as in `silver.tb_curso` |
  | `data_carga` | TIMESTAMP | time gold wrote the version |
  | `__START_AT` | TIMESTAMP | change time from which the version is valid |
  | `__END_AT` | TIMESTAMP | change time at which the version stopped being valid; empty for the current version |

  The record source (`origem`) is not a column of the dimension (owner, 2026-11-05).

- **FR-003**: The dimension MUST be SCD type 2: each change of a course opens a new
  version and closes the previous one; no version is overwritten or removed. Its grain is
  one version of one course, plus the two members of FR-008.
- **FR-004**: Changes MUST be keyed on `curso_uuid` and applied in change-time order,
  with the same key, order and delete condition as `silver.tb_curso` (constitution,
  Principle I), so that the current version of each course always equals the silver row.
- **FR-005**: A deletion MUST close the course's current version and MUST NOT remove any
  row.
- **FR-006**: `sk_curso` MUST be a single column, unique, never empty, and MUST keep its
  value for a given version across every pipeline update, full refresh included. A
  mechanism that can reassign keys MUST NOT be used. Course versions' keys MUST be
  non-negative, so that a negative key always means a member of FR-008.
- **FR-007**: The dimension MUST retain `curso_uuid` as its business key, the identifier
  delivered by the source (constitution, Principle VII), so that a fact resolves the
  version by `curso_uuid` and the fact's date.
- **FR-008**: The dimension MUST contain two members with fixed surrogate keys and fixed
  business keys: "unknown" (`Desconhecido`) and "not applicable" (`Não se aplica`). Their
  text attributes carry that label, their price is empty, and they are always current.
- **FR-009**: The dimension MUST NOT declare expectations: this spec requests none
  (constitution v2.0.0, Principle III). Key uniqueness and presence MUST be verified by
  query after a load.
- **FR-010**: The dimension reads the bronze change feed through its boundary view
  `vw_bronze_tb_curso`, not `silver.tb_curso`, which keeps no history (constitution,
  Principle I exception). It MUST NOT apply cleansing or business rules to the feed beyond
  excluding the change-control and lineage columns and the record source.
- **FR-011**: The dimension MUST NOT reference another dimension, and MUST carry
  `quality` = `gold`.
- **FR-012**: The definitions MUST follow the constitution: SQL, current syntax, gold
  dataset types, numbered files in the pipeline's gold folder.
- **FR-013**: The dimension, its source, its bronze dependency, grain, keys, members and
  SCD type MUST be described in the project documentation, replacing the earlier
  pipeline's description of `dim_curso`.

### Key Entities

- **Course version**: one state of one course in the catalog, valid from one change time
  until the next change of that course (or open, if current), with its own surrogate key.
- **Default member**: the "unknown" or "not applicable" course, a fixed row that facts
  point to when a course is missing or does not apply.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the initial catalog, `dim_curso` has 3 course rows + 2 members = 5
  rows, and 3 current course rows, one per course.
- **SC-002**: 0 rows have an empty `sk_curso` or `curso_uuid`; no two rows share an
  `sk_curso`; no course has more than one current row.
- **SC-003**: For 100% of courses in `silver.tb_curso`, the current version's name, level
  and price equal silver's, and the number of current course rows equals silver's row
  count.
- **SC-004**: After a second update with no new data, 100% of recorded rows and surrogate
  keys are unchanged, members included.
- **SC-005**: Exactly 1 "unknown" row and 1 "not applicable" row exist, both current.
- **SC-007**: 100% of rows have a filled `data_carga`, and the dimension has exactly the 8
  columns of FR-002.
- **SC-006**: At the live demo, after the update, the updated course has 2 rows (one
  closed at `247.00`, one current at `147.00`) and the other courses 1 each; after the
  deletion, the deleted course has 0 current rows and keeps both versions.

## Assumptions

- **The surrogate key is deterministic.** The request gives no type for `sk_curso`. The
  earlier pipeline used an identity column, which the platform does not support on the
  target of a change feed (`doc/known-issues.md`). As for `dim_usuario` (feature 009) and
  `dim_codigos` (feature 011), where the owner chose a deterministic key, the key of a
  version is computed from what identifies it, the course identifier and the change time
  that opened it, so it is the same on every recomputation. Its exact expression is a
  planning decision.
- **History column names** are the platform's `__START_AT` and `__END_AT` (owner,
  2026-11-05). They are what the constitution names for current-version queries
  (`__END_AT IS NULL`, Principles V and VII).
- **No record source** (owner, 2026-11-05). Every course comes from one source, so
  `origem` would always be `DATABASE`. The constitution's sentence that `tb_curso` and
  `dim_curso` "carry the same price type and record source" (Principle I, course feed
  exception) describes what the shared view delivers; planning checks it in the
  Constitution Check.
- **`data_carga`** is the time gold wrote the version. Closing a version later sets only
  its `__END_AT`.
- **Source**: `workspace.bronze.dados_database`, through `vw_bronze_tb_curso`, as the
  constitution prescribes for this dimension (Principle I exception) and the diagram shows.
- **The validity period comes from the change time** (`timestamp_change`) of the feed, not
  from when the pipeline ran, so history reflects the catalog's own timeline.
- **Default members** are required by the constitution (Principle VII) even though the
  request does not list them. Their key values follow the other dimensions: `-1` and `-2`.
- **Updates and deletions are proven at the live demo, not during implementation**, as
  for `silver.tb_curso` (feature 008). On 2026-11-05 the feed holds only the three inserts
  (`beginner`, `intermediate`, `advanced`; all at one change time). Implementation MUST NOT
  run the generator's `update row` or `delete row`. It proves User Stories 1 and 4 (SC-001
  to SC-005); User Stories 2 and 3 (SC-006) are proven when the owner runs `update row`
  and `delete row` during the talk, and rest until then on the declared key, change-time
  order and delete condition.
- Resolving the version in effect for a fact is `fato_venda`'s concern; this feature only
  provides the validity period.
- `fato_venda`, `obt_acesso` and the other dimensions are out of scope.
- All data is synthetic.
