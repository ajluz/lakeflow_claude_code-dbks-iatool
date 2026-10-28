# Feature Specification: Silver Course Catalog as the Latest Version of Each Course

**Feature Branch**: `008-silver-tb-curso`

**Created**: 2026-10-28

**Status**: Draft

**Input**: User description: "generate the tb_curso table load. the tb_curso will have 1 source - bronze_database. the table must have the follow fields: 1. all fields from bronze dados_database, 2. origem with the constant value 'DABATASE' 3. data_carga the table must do an scd type 1. delitions should be deleted keeping the latast correct value. the control system columns must be deleted from the silver table."

## Clarifications

### Session 2026-10-28

- Q: Should implementation run the generator's course update and then its course deletion in the landing volume, to prove that updates overwrite and deletions remove? → A: C. Run neither. Implementation validates the initial inserts only; the update and the deletion are kept for the live demo at the talk.
- Q: Which name should the boundary view over the bronze course feed have: `vw_bronze_dados_database`, as the constitution names it, or `vw_bronze_tb_curso`, as the architecture diagram draws it? → A: B. `vw_bronze_tb_curso`, the diagram's name, with a constitution amendment to allow it.
- Q: Should the course price in tb_curso stay a floating-point number as delivered (247.0), or be stored as a two-decimal exact amount (247.00), like the money columns of tb_venda? → A: B. Store it as an exact two-decimal amount, matching tb_venda's money columns.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One current row per course (Priority: P1)

As the project owner, I want `workspace.silver.tb_curso` to hold exactly one row per
course in the catalog, with its latest name, level and price, so that sales and accesses
can be described by the course as it is today.

**Why this priority**: the catalog is the reference every sale and access points to
through its course key. Without it, silver has no description of a course.

**Independent Test**: after a run on the initial catalog, `tb_curso` has three rows, one
per course, each with the values of its insert and `origem = 'DATABASE'`.

**Acceptance Scenarios**:

1. **Given** the three inserts of the initial catalog, **When** the run completes,
   **Then** `tb_curso` has three rows, with `curso_uuid`, `nome_curso` and `nivel_curso`
   as delivered, `valor_curso` as an exact two-decimal amount (`247.00`, `997.00`,
   `2497.00`), `origem = 'DATABASE'` and a load time.
2. **Given** a course row, **When** its columns are read, **Then** it carries none of the
   change-control columns (the change type and the change time) and none of the bronze
   lineage columns.
3. **Given** a run with no new change, **When** it completes, **Then** `tb_curso` is
   unchanged.

---

### User Story 2 - Updates overwrite in place (Priority: P1)

As the project owner, I want a course update to replace the course's values in place,
without keeping the old version, so that the table always shows the current catalog.

**Why this priority**: this is the "SCD type 1" behavior the request asks for, and it is
what the talk demonstrates on this table. History belongs to the gold course dimension.

**Independent Test**: at the live demo, after the generator delivers the update of
*Construindo um Data Lakehouse com SQL e DLT* to `147.00`, `tb_curso` still has three rows,
and that course's price is `147.00`. Implementation does not run this test (Clarifications,
2026-10-28).

**Acceptance Scenarios**:

1. **Given** an update of a course, **When** the run completes, **Then** the course has
   exactly one row, with the updated values and a new load time.
2. **Given** an update, **When** the table is read, **Then** the previous values are not
   in it anywhere.
3. **Given** two changes to the same course delivered in one run, **When** the run
   completes, **Then** the row holds the values of the change with the latest change
   time.

---

### User Story 3 - Deletions remove the course (Priority: P1)

As the project owner, I want a course deletion to remove that course from the table,
while every other course keeps its latest correct values, so that a withdrawn course no
longer appears as current.

**Why this priority**: the request asks for deletions to be applied, and the generator's
change feed ends with one.

**Independent Test**: at the live demo, after the generator delivers the deletion of
*Construindo um Data Lakehouse com SQL e DLT*, `tb_curso` has two rows: the other two
courses, unchanged. Implementation does not run this test (Clarifications, 2026-10-28).

**Acceptance Scenarios**:

1. **Given** a deletion of a course, **When** the run completes, **Then** the course has
   no row in `tb_curso`.
2. **Given** a deletion of one course, **When** the run completes, **Then** every other
   course keeps the values of its latest change.
3. **Given** a deletion whose change time is earlier than the course's latest update,
   **When** the run completes, **Then** the deletion does not remove the newer version:
   changes are applied in change-time order, not in arrival order.

---

### Edge Cases

- **Deleted course still referenced.** Sales and accesses of a deleted course keep its
  `curso_uuid`. Once the course is deleted, they no longer join `tb_curso`. The gold
  course dimension keeps the history (out of scope).
- **The same course inserted again after a deletion.** A later insert with a later
  change time brings the course back as one row.
- **Two changes with the same change time for one course.** The order between them is
  undefined. The generator writes each change in its own run, so this is not expected;
  planning states how a tie is resolved.
- **A change with an empty course identifier.** It cannot be applied to any course. It is
  counted by a rule (FR-008) and does not create a row.
- **The initial catalog delivered again.** The generator's initial setup overwrites its
  file. A second delivery of the same inserts carries the same identifiers and replaces
  each course with the same values; the row count stays three.
- **Price type.** The price arrives as a floating-point number (`247.0`) and is stored
  as an exact two-decimal amount (`247.00`), like `tb_venda`'s money columns. The
  conversion is lossless for every price the generator writes (`247.00`, `997.00`,
  `2497.00`, `147.00`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a conformed silver table
  `workspace.silver.tb_curso`, fed incrementally from the course catalog's change feed in
  `workspace.bronze.dados_database`.
- **FR-002**: The table MUST have exactly these columns:

  | Column | Type | From |
  |---|---|---|
  | `curso_uuid` | STRING | `curso_uuid`, as delivered |
  | `nome_curso` | STRING | `nome_curso`, as delivered |
  | `nivel_curso` | STRING | `nivel_curso`, as delivered |
  | `valor_curso` | DECIMAL(9,2) | `valor_curso`, converted to an exact two-decimal amount (`247.0` becomes `247.00`) |
  | `origem` | STRING | `DATABASE` |
  | `data_carga` | TIMESTAMP | load time of the change that set the row |

- **FR-003**: The change-control columns `change_type` and `timestamp_change`, and the
  bronze lineage columns `processing_time`, `source_file_name` and `_rescued_data`,
  MUST NOT be columns of the table.
- **FR-004**: The table MUST hold one row per `curso_uuid`: the values of the latest
  change for that course, ordered by `timestamp_change` (SCD type 1). An update MUST
  overwrite the row in place; earlier values are not kept.
- **FR-005**: A change whose `change_type` is `delete` MUST remove the course's row.
  Every other course MUST keep the values of its latest change.
- **FR-006**: Changes MUST be applied in `timestamp_change` order, so that a late-arriving
  older change does not overwrite a newer one.
- **FR-007**: The bronze source MUST be read through a boundary view named
  `vw_bronze_tb_curso` that excludes `source_file_name` and `_rescued_data`, as the
  constitution requires for every read of bronze. The name follows the diagram, which
  needs a constitution amendment (Assumptions).
- **FR-008**: The table MUST declare these rules, each of which only counts failures:
  - `check_curso_uuid`: `curso_uuid` is not empty;
  - `check_nome_curso`: `nome_curso` is not empty;
  - `check_valor_curso`: `valor_curso` is greater than zero (an empty price fails).
- **FR-009**: The table MUST carry `quality` = `silver`.
- **FR-010**: Changes already applied MUST NOT be applied again by a later run.
- **FR-011**: The table MUST NOT derive a hash key. It keeps the identifier delivered by
  the source, under the constitution's bounded exception for `tb_curso`.
- **FR-012**: The definitions MUST follow the constitution: SQL, current syntax, declared
  as streaming, numbered files in the silver folder. The plan MUST state that the target
  is SCD type 1, its key, its sequence and its delete condition.
- **FR-013**: The table, its source, key, sequence, delete condition and rules MUST be
  described in the project documentation, replacing the earlier pipeline's description of
  `tb_curso`.

### Key Entities

- **Course** (`tb_curso` row): one course of the catalog in its current version,
  identified by `curso_uuid`, with name, level and price.
- **Course change** (`bronze.dados_database` row): an insert, update or delete of one
  course, with the time it happened. It is applied to the table and then has no row of its
  own.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the initial catalog, `tb_curso` has 3 rows, one per course, with
  values equal to the inserts.
- **SC-002**: At the live demo, after the update, `tb_curso` still has 3 rows, and the updated course's
  price is `147.00`; 0 rows hold the old price `247.00`.
- **SC-003**: At the live demo, after the deletion, `tb_curso` has 2 rows, the deleted course has 0 rows,
  and the other two courses are unchanged.
- **SC-004**: At every point, the number of rows equals the number of distinct courses
  whose latest change is not a deletion, with a difference of 0, and no `curso_uuid`
  appears twice.
- **SC-005**: 100% of rows have `origem = 'DATABASE'` and a non-empty `data_carga`; 0
  columns of the table are change-control or lineage columns.
- **SC-006**: The quality view lists the three rules, each with failed counts equal to
  those computed directly from the source.
- **SC-007**: A run with no new change modifies 0 rows.

## Assumptions

- **The record source is `DATABASE`.** The request writes `'DABATASE'`. The constitution
  fixes `DATABASE` as the record source of this source (Principle VI), and the earlier
  pipeline used it. The spelling is treated as a typo.
- **"Control system columns"** means the change-control columns `change_type` and
  `timestamp_change`, plus the bronze lineage columns `processing_time`,
  `source_file_name` and `_rescued_data`. They drive the change but are not attributes of
  a course. The earlier pipeline excluded the same five.
- **"All fields from bronze dados_database"** therefore means the four course attributes:
  `curso_uuid`, `nome_curso`, `nivel_curso`, `valor_curso`, with their names as delivered.
  Their types are kept, except `valor_curso`, which becomes `DECIMAL(9,2)` (owner,
  2026-10-28).
- **"Deletions should be deleted keeping the latest correct value"** means: a deletion
  removes the course's row, and every other course keeps the values of its latest change.
  Change time decides the order.
- **`bronze_database`** means `workspace.bronze.dados_database`, the change feed of feature
  003. The feed's delete row carries the course's last values, so nothing needs to be
  recovered from it.
- **No hash key**: the constitution exempts `tb_curso` (Principle VI). Sales and accesses
  already compute `curso_uuid` as `md5` of the course name, equal to the catalog's
  identifier.
- **The request names no quality rule.** Principle III requires at least one, so three
  counting rules are declared (FR-008). None removes a change, so no exclusion is needed.
- **Updates and deletions are proven at the live demo, not during implementation**
  (owner, 2026-10-28). On 2026-10-28 the source holds only the three inserts.
  Implementation MUST NOT run the generator's `update row` or `delete row`, so the
  catalog reaches the talk in its initial state. Implementation proves User Story 1
  (SC-001, SC-004, SC-005, SC-006, SC-007). User Stories 2 and 3 (SC-002, SC-003) are
  proven when the owner runs `update row` and then `delete row` during the talk; their
  behavior before then rests on the declared key, change-time order and delete
  condition.
- **The boundary view is `vw_bronze_tb_curso`** (owner, 2026-10-28), the name in
  `doc/lakeflow_architecture.png`. The constitution names it `vw_bronze_dados_database`,
  both in Principle I's `dim_curso` exception and through its naming rule
  `vw_<source zone>_<dataset>`. A constitution amendment that allows the diagram's name
  MUST be approved before planning; it also changes the view that `gold.dim_curso` will
  read.
- The gold course dimension (`dim_curso`, SCD type 2) is out of scope. It will read the
  bronze feed with the same key, sequence and delete condition (Principle I).
- All data is synthetic.
