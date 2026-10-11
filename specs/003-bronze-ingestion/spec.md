# Feature Specification: Bronze Ingestion of the Three Landing Sources

**Feature Branch**: `003-bronze-ingestion`

**Created**: 2026-10-11

**Status**: Draft

**Input**: User description: "under the src folder - code that will be used on Lakeflow Declarative Pipelines, I want you to create the specify for generate 3 sql codes. 1 for each source inside the landing volume on bronze schema. it will need to use autoloader and it must to be a stream table. add to the tables the processing_time column derived from a current_timestamp() function and the source_file_name derived from _metadata.file_path. each of the tables must to have the properties quality broze."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ingest each landing source into its own bronze table (Priority: P1)

As the project owner, I want each of the three sources that arrive in the landing volume to
be loaded into its own table in the bronze layer, exactly as it arrived, so that the rest
of the pipeline has a faithful, queryable copy of the raw data to build on.

The three sources are the site events delivered as a stream of JSON files, the corporate
sales delivered by partner companies as CSV files, and the course catalog change feed
delivered as CSV files.

**Why this priority**: bronze is the entry point of the medallion architecture. Silver and
gold cannot exist until the raw data is in tables, and the talk's first demonstration is
this ingestion.

**Independent Test**: with files present in the three landing folders, run the pipeline
that contains the three definitions and confirm that three bronze tables exist, that each
holds as many rows as its source files contain, and that every source column is present
with its original name.

**Acceptance Scenarios**:

1. **Given** the three landing folders contain files, **When** the pipeline is run,
   **Then** the tables `dados_api`, `dados_files` and `dados_database` exist in the bronze
   layer, one per source.
2. **Given** a source file with a known number of records, **When** it has been ingested,
   **Then** the bronze table of that source contains exactly that number of rows for that
   file.
3. **Given** a source record, **When** it is read from the bronze table, **Then** every
   field of the source is present under its original name and with its original value, and
   no record was filtered out, corrected or deduplicated.
4. **Given** the JSON source has nested fields, **When** it is ingested, **Then** the
   nesting is preserved and the nested fields can be queried by name.
5. **Given** the three definitions, **When** the owner inspects where they live, **Then**
   there is one definition file per table, and each file is named after its table.

---

### User Story 2 - Know when and from where every row came (Priority: P1)

As the project owner, I want every bronze row to record the moment it was processed and the
file it was read from, so that any row can be traced back to its origin and any load can be
audited.

**Why this priority**: lineage is the reason bronze is trusted. Once sources are merged in
silver, the file a row came from is the only way to investigate a bad record. The request
names these two columns explicitly, so they carry the same priority as the ingestion.

**Independent Test**: after an ingestion, query any bronze row and confirm it has a
processing time close to the moment of the run and the full path of a file that exists in
the landing folder of that source.

**Acceptance Scenarios**:

1. **Given** a row in any of the three bronze tables, **When** it is read, **Then** it has
   a column `processing_time` holding the timestamp at which the row was processed.
2. **Given** a row in any of the three bronze tables, **When** it is read, **Then** it has
   a column `source_file_name` holding the full path of the file the row was read from.
3. **Given** two files ingested from the same source, **When** the rows are grouped by
   `source_file_name`, **Then** the rows of each file are attributed to that file and to
   no other.
4. **Given** each of the three bronze tables, **When** its properties are inspected,
   **Then** it carries the property `quality` with the value `bronze`.

---

### User Story 3 - Pick up new files without reloading old ones (Priority: P2)

As the project owner, I want each run to ingest only the files that arrived since the
previous run, so that the demo can add data between runs and show it flowing through
without duplicating what is already loaded.

**Why this priority**: the talk demonstrates incremental processing and change data
capture by adding files between runs. The first load already delivers value; incremental
behavior is what makes the following demonstrations possible.

**Independent Test**: run the pipeline, note the row count of a table, add one new file to
that source's folder, run the pipeline again, and confirm the count grew by exactly the
number of records in the new file.

**Acceptance Scenarios**:

1. **Given** a completed run, **When** the pipeline is run again with no new files,
   **Then** no table gains rows.
2. **Given** a completed run, **When** a new file arrives in one source's folder and the
   pipeline is run again, **Then** only that source's table gains rows, by exactly the
   number of records in the new file.
3. **Given** a file was ingested in an earlier run, **When** the pipeline is run again,
   **Then** the rows of that file are not ingested a second time.
4. **Given** rows ingested in different runs, **When** their `processing_time` values are
   compared, **Then** rows from the later run have a later time.

---

### Edge Cases

- A landing folder is empty or does not exist yet, because no data was generated for that
  source: the table's columns come from the files, so there is nothing to build the table
  from. The run must fail for that source with a message that names the folder, and the
  owner generates the data and runs again. Generating data for all three sources is a
  prerequisite of the first run.
- A file contains a value that does not fit the type inferred for its column, or a column
  that was not there before: the record must be kept, with the unexpected content
  preserved in the rescued-data column, and must not be dropped.
- The files of a source carry marker or metadata files written by the tool that produced
  them: these must not become rows.
- The folder that the stream generator uses for its own bookkeeping sits beside the source
  folders in the landing volume: it must not be read as a source.
- A source's files are replaced by new files with the same content (the course catalog's
  initial load is rewritten on each run of its generator): the new files are new arrivals
  and are ingested again. Bronze keeps every delivery; deciding which one counts is a
  silver concern.
- A CSV file has a header row: the header must give the column names and must not be
  ingested as a data row.
- A text value contains the field separator: it must be read as one value when it is
  quoted in the file.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide three ingestion definitions, one for each landing
  source, each producing one table in the bronze schema of the `workspace` catalog.
- **FR-002**: The three tables MUST be named and fed as follows:

  | Table | Source | Landing folder | File format |
  |---|---|---|---|
  | `dados_api` | site events from the API | `stream/` | JSON |
  | `dados_files` | corporate sales from partner companies | `files/` | CSV with header, comma-separated |
  | `dados_database` | course catalog change feed | `database/` | CSV with header, comma-separated |

- **FR-003**: Each table MUST be a streaming table: it is fed incrementally and only ever
  appended to.
- **FR-004**: Each table MUST be loaded with Auto Loader, the platform's incremental file
  ingestion, reading from its folder in the volume `workspace.bronze.landing`.
- **FR-005**: Each table MUST contain every column of its source, with the source's column
  names, and with column types inferred from the data.
- **FR-006**: Each table MUST add a column `processing_time` whose value is the current
  timestamp at the moment the row is processed.
- **FR-007**: Each table MUST add a column `source_file_name` whose value is the path of
  the file the row was read from, taken from the file metadata that the ingestion exposes.
- **FR-008**: Each table MUST keep the rescued-data column that the ingestion provides, so
  that content which does not fit the inferred schema is preserved with its record.
- **FR-009**: Each table MUST carry the table property `quality` with the value `bronze`.
- **FR-010**: The definitions MUST NOT filter, cast, rename, deduplicate or drop source
  records or columns, and MUST NOT declare a quality rule that removes rows or stops the
  run.
- **FR-011**: A file that was already ingested MUST NOT be ingested again by a later run.
- **FR-012**: A run MUST ingest files that arrived after the previous run, and only those.
- **FR-013**: The definitions MUST be written in SQL, in the current syntax of Lakeflow
  Spark Declarative Pipelines, one file per table, each file named after its table.
- **FR-014**: The three files MUST live under `src/`, in the bronze folder of the pipeline
  source, as the project constitution's repository layout prescribes.
- **FR-015**: The definitions MUST NOT write to, move or delete anything in the landing
  volume.
- **FR-016**: The three tables and their columns MUST be described in the project
  documentation.

### Key Entities

- **Landing source**: a folder in the landing volume that receives the files of one
  origin. Three exist: `stream/` (site events), `files/` (corporate sales) and `database/`
  (course catalog changes). Files are added over time and are never changed in place.
- **Bronze table**: the raw, append-only copy of one landing source. It has the source's
  columns, the two lineage columns, the rescued-data column, and the `quality` property.
- **Site event (`dados_api`)**: one visit to the site, with the access time, the address
  and device it came from, and an optional nested payload describing the user, the product
  and the payment.
- **Corporate sale (`dados_files`)**: one course sold to an employee of a partner company,
  with the sale date, the company, the employee's details, the course, its price and the
  discount.
- **Course change (`dados_database`)**: one change to a course in the catalog, with the
  course key, name, level and price, the kind of change (insert, update, delete) and when
  it happened.
- **Lineage columns**: `processing_time` (when the row was processed) and
  `source_file_name` (which file it came from), present in all three tables.
- **Ingestion definition**: the description of one bronze table, kept as one file of the
  pipeline's source.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After one run with files in all three landing folders, 3 bronze tables exist,
  one per source.
- **SC-002**: For each source, the number of rows in its table equals the number of records
  in its landing files: 100% of delivered records are present and none is duplicated.
- **SC-003**: 100% of rows in the three tables have a non-empty `processing_time` and a
  non-empty `source_file_name`.
- **SC-004**: For 100% of rows, `source_file_name` is the path of a file that exists in the
  landing folder of that table's source.
- **SC-005**: 100% of source columns are present in the corresponding table under their
  original names.
- **SC-006**: A second run with no new files adds 0 rows to every table.
- **SC-007**: After one new file is delivered to one source, the next run adds exactly that
  file's record count to that source's table and 0 rows to the other two.
- **SC-008**: All 3 tables report the `quality` property as `bronze`.
- **SC-009**: The owner can go from generated files in the landing volume to three queryable
  bronze tables with a single run of the pipeline, without editing any definition.

## Assumptions

- "Under the src folder" means the pipeline source folder that the constitution reserves
  for project code, with a subfolder for the bronze layer. The exact path is fixed in the
  plan.
- "1 for each source inside the landing volume" refers to the three sources the project
  already defines and its data generators already write: `stream/`, `files/` and
  `database/`.
- The table names `dados_api`, `dados_files` and `dados_database` are kept from the
  project's earlier pipeline and documentation, so that existing queries, notebooks and
  documentation keep working. The request does not name the tables.
- File formats follow what the generators produce: JSON for `stream/`; CSV with a header
  row and comma separator for `files/` and `database/`.
- Column types are inferred from the data, not declared, as in the project's earlier
  bronze code. Declaring an explicit schema is out of scope.
- "quality broze" in the request means the table property `quality` = `bronze`, as the
  constitution requires for every bronze table.
- The feature delivers the three definition files. A pipeline in the workspace that points
  at them is needed to run and validate them; creating that pipeline for validation is part
  of the work, but managing it as a versioned, deployable resource is a later step.
- Source files must exist before the definitions can be validated. Generating them is done
  with the project's existing data generators and is not part of this feature.
- The schemas and the landing volume already exist, from features 001 and 002, with access
  restricted to `arthur.luz@dataslight.com.br`. The tables created by the pipeline inherit
  that restriction; no additional access rule is defined here.
- Silver and gold tables, validation, quarantine and change data capture are out of scope.
  They are later steps and consume these bronze tables.
- The environment is Databricks Free Edition, where the stream of site events is simulated
  by files written in batches. The ingestion treats them as files arriving over time.
- All data is synthetic.
