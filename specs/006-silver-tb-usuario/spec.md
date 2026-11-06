# Feature Specification: Silver User Table from API Events and Partner Files

**Feature Branch**: `006-silver-tb-usuario`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "generate the tb_usuario with the follow constraints: 1. CONSTRAINT check_sexo_usuario = should be M or F. in that case droip the row. CONSTRAINT check_email_usuario = email_usuario must have %@%. if not the email is not valid. this constraint it's just informative. the tb_usuario will have 2 sources - bronze_api and bronze_files. from bronze_api the table must have the follow fields: 1. usuario_uuid where will be a uuid field thar will concatenate the follow fields: timestamp_acesso, payload.info_usuario.nome. 2. nome_usuario 3. email_usuario 4. idade usuario - as integer 5. sexo_usuario 6. estado_usuario 7. profissao_usuario 8. origem 9. data_carga. from bronze_files the table must have the follow fields: 1. usuario_uuid where will be a uuid field thar will concatenate the follow fields: nome_empresa and nome_funcionario. 2. nome_usuario 3. email_usuario 4. idade_usuario - as integer 5. sexo_usuario 6. estado_usuario 7. profissao_usuario 8. empresa_usuario 8. origem 9. data_carga"

## Clarifications

### Session 2026-11-06

- Q: Should `check_sexo_usuario` keep removing users whose sex is not `M` or `F`? → A: No
  (owner). The rule only records the error: `ON VIOLATION DROP ROW` is commented out in
  the code, and both flow views put the sex as empty (NULL) when it is not `M` or `F`. The
  rule still counts those rows as failures. The users dropped before were brought back by
  a full refresh of `tb_usuario`, `dim_usuario` and `fato_venda` approved by the owner.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Users from the site in one conformed table (Priority: P1)

As the project owner, I want every user who appears in a valid site event to become a row
of `workspace.silver.tb_usuario`, with name, email, age, sex, state and profession, so
that the site's audience can be analysed.

**Why this priority**: the API is the largest source of users, and its user key already
exists (feature 005), so this half of the table can be delivered first.

**Independent Test**: after a run, every valid event that carries a user has one row in `tb_usuario` with `origem = 'API'` and the
same `usuario_uuid` as its row in `tb_acesso`.

**Acceptance Scenarios**:

1. **Given** a valid API event with a user, **When** the run completes, **Then**
   `tb_usuario` has a row with that event's `usuario_uuid`, name, email, age as a whole
   number, sex, state and profession, and `origem = 'API'`.
2. **Given** a valid API event without a user, **When** the run completes, **Then** it
   produces no row in `tb_usuario`.
3. **Given** an API event in quarantine, **When** the run completes, **Then** it produces
   no row in `tb_usuario`.
4. **Given** an API user row, **When** its `usuario_uuid` is compared with `tb_acesso`,
   **Then** it is the same value, so accesses join their user.
5. **Given** an API user row, **When** `empresa_usuario` is read, **Then** it is empty,
   because site users carry no company.

---

### User Story 2 - Employees of partner companies in the same table (Priority: P1)

As the project owner, I want every employee who appears in the partner companies' sales
files to become a row of the same table, with their company, so that site users and
corporate buyers can be analysed together.

**Why this priority**: the request puts both sources in one table. Without the files
source, corporate buyers would have no user record.

**Independent Test**: after a run, every distinct employee of the files source appears
exactly once in `tb_usuario` with
`origem = 'ARQUIVO'` and their company in `empresa_usuario`.

**Acceptance Scenarios**:

1. **Given** a sales file row for an employee, **When** the run completes, **Then**
   `tb_usuario` has a row with `usuario_uuid` derived from the company name and the
   employee name, the employee's name, email, age as a whole number, sex, state,
   profession, company, and `origem = 'ARQUIVO'`.
2. **Given** the sales files of 2026-10-18, **When** the run completes, **Then** each
   employee (company, name) has exactly one row in `tb_usuario`, because each appears in
   exactly one sales row. Re-delivery of an employee is not merged (owner's decision,
   2026-10-18): the uniqueness check after each load would report it.
3. **Given** two employees with the same name at different companies, **When** the run
   completes, **Then** they are two rows, because the company is part of the key.

---

### User Story 3 - Measure impossible sex values and invalid emails (Priority: P1)

As the project owner, I want users whose sex is not `M` or `F` kept with an empty sex and
counted, and users with an email that has no `@` counted but kept. Both rules are then
informative: the pipeline shows the errors without losing users (owner, 2026-11-06).

**Why this priority**: the two rules are the point of this table in the demonstration.

**Independent Test**: after a run, the data quality view shows both rules, with no row
dropped. The sex rule's failed count equals the number of candidate user rows whose sex
is not `M` or `F`, and those rows are in the table with an empty sex. The email rule's
failed count equals the number of candidate user rows whose email has no `@`.

**Acceptance Scenarios**:

1. **Given** a user whose sex is `X`, empty or anything other than `M` or `F`, **When** the
   run completes, **Then** the user is in `tb_usuario` with an empty `sexo_usuario` and is
   counted as a failure of `check_sexo_usuario`, and the run does not stop.
2. **Given** a user whose email has no `@` (for example `usuario_ab12cd34#yahoo.com`) or
   no email at all, **When** the run completes, **Then** the user is in `tb_usuario` and
   counted as a failure of `check_email_usuario`, and the run does not stop.
3. **Given** users counted by `check_sexo_usuario`, **When** the owner looks for them,
   **Then** they are in `tb_usuario` with an empty sex, not in quarantine, and no
   reconciliation exclusion is needed.

---

### Edge Cases

- An age that is not a whole number, or is empty: `idade_usuario` is empty. The row is
  kept and the rules are unaffected.
- A sex value in lower case (`m`, `f`): it is not `M` or `F` as written, so it becomes
  empty and is counted by the rule; the row is kept. The generator writes only `M`, `F` and `X`.
- The same person visits the site several times: each visit yields a different
  `usuario_uuid`, because the key includes the access time, as requested. So the person
  has one row per visit.
- An employee delivered again in a later file: the table would receive a second row with
  the same key. The table appends and does not merge (owner's decision, 2026-10-18). The
  uniqueness check after each load reports it, and deduplication would then be planned as
  a change.
- An API key and a files key are equal by chance: they are built from different fields,
  so this does not happen in practice. Uniqueness of `usuario_uuid` across the whole table
  is still verified.
- A sales file row without an employee name: its key is built from the company and an
  empty name. Planning checks whether such rows exist.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a conformed silver table
  `workspace.silver.tb_usuario`, fed incrementally from two sources: the valid API events
  of feature 004, and the partner companies' sales files in
  `workspace.bronze.dados_files`.
- **FR-002**: The table MUST have these columns, filled per source as follows:

  | Column | Type | From API events | From sales files |
  |---|---|---|---|
  | `usuario_uuid` | STRING | key from `timestamp_acesso` and `payload.info_usuario.nome` | key from `nome_empresa` and `nome_funcionario` |
  | `nome_usuario` | STRING | `payload.info_usuario.nome` | `nome_funcionario` |
  | `email_usuario` | STRING | `payload.info_usuario.email` | `email_funcionario` |
  | `idade_usuario` | INT | `payload.info_usuario.idade`, as a whole number | `idade`, as a whole number |
  | `sexo_usuario` | STRING | `payload.info_usuario.sexo` when `M` or `F`, else empty | `sexo` when `M` or `F`, else empty |
  | `estado_usuario` | STRING | `payload.info_usuario.estado` | `estado` |
  | `profissao_usuario` | STRING | `payload.info_usuario.profissao` | `profissao` |
  | `empresa_usuario` | STRING | empty | `nome_empresa` |
  | `origem` | STRING | `API` | `ARQUIVO` |
  | `data_carga` | TIMESTAMP | load time | load time |

- **FR-003**: The API rows MUST come only from valid events that carry a user, and their
  `usuario_uuid` MUST be the value already defined for the API source (feature 005). It is
  reused, not recomputed.
- **FR-004**: The files key MUST be a deterministic hash key built from `nome_empresa` and
  `nome_funcionario`, defined once and reused by every later table that refers to a files
  user (for example sales).
- **FR-005**: Each source MUST feed the table through its own flow. Sources MUST NOT be
  combined into one query.
- **FR-006**: The files source MUST be read through a boundary view that excludes
  `source_file_name` and `_rescued_data`, as the constitution requires for every read of
  bronze.
- **FR-007**: `usuario_uuid` MUST be unique in the table. Each source is appended through
  its own flow, without merging; uniqueness holds because each key occurs once in the
  current data. It MUST be verified after every load, and a repeated key MUST be reported
  to the owner (owner's decision, 2026-10-18).
- **FR-008**: `sexo_usuario` MUST be `M`, `F` or empty: each flow view writes it as empty
  (NULL) when the source sex is anything other than `M` or `F` (owner, 2026-11-06).
- **FR-009**: The table MUST declare `check_sexo_usuario`: `sexo_usuario` is `M` or `F`. A
  failure, an empty sex included, MUST only be counted: no row is removed or quarantined.
  The former `ON VIOLATION DROP ROW` stays commented out in the code (owner, 2026-11-06).
- **FR-010**: The table MUST declare `check_email_usuario`: `email_usuario` contains `@`.
  A failure, an empty email included, MUST only be counted.
- **FR-011**: The table MUST declare that `usuario_uuid` is never empty.
- **FR-012**: The table MUST carry `quality` = `silver`.
- **FR-013**: Rows already loaded MUST NOT be loaded again by a later run.
- **FR-014**: The definitions MUST follow the constitution: SQL, current syntax, declared
  as streaming, numbered files in the silver folder.
- **FR-015**: The table, its sources, keys and rules MUST be described in the project
  documentation, replacing the earlier pipeline's description. The business key columns of
  both user keys MUST be listed.

### Key Entities

- **User** (`tb_usuario` row): a person known to the business, either a site user (one
  row per visit with a user, by the request's key) or a partner company's employee (one
  row per company and name). Identified by `usuario_uuid`.
- **Site user**: taken from the user part of a valid API event. Reached from `tb_acesso`
  through `usuario_uuid`.
- **Corporate user**: taken from a sales file row, together with the company. Reached
  from later sales tables through `usuario_uuid`.
- **User rules**: `check_sexo_usuario` and `check_email_usuario` (both count only), and the not-empty rule on `usuario_uuid`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: API rows in `tb_usuario` = valid API events with a user, with a difference
  of 0.
- **SC-002**: Files rows in `tb_usuario` = distinct employees (company, name) in the sales
  files, with a difference of 0.
- **SC-003**: Every row has a sex of `M`, `F` or empty, the empty ones equal the sex
  rule's failed count, and 0 rows have an empty `usuario_uuid`. No two rows share a `usuario_uuid`.
- **SC-004**: The quality view lists both rules, each with failed counts equal to those
  computed directly from the sources.
- **SC-005**: 100% of API rows join `tb_acesso` on `usuario_uuid`, apart from users whose
  access `tb_acesso` dropped for the impossible address. Those are counted and explained.
- **SC-006**: 100% of rows have `origem` in {`API`, `ARQUIVO`}, a non-empty `data_carga`,
  and `empresa_usuario` filled exactly on the `ARQUIVO` rows.
- **SC-007**: A second run with no new data adds 0 rows.

## Assumptions

- The request first asked to drop rows failing `check_sexo_usuario` (a declared exclusion,
  constitution v1.7.0). On 2026-11-06 the owner replaced it: the users are kept with an
  empty sex and the rule only counts them, because their sales and accesses exist and
  should keep their user.
- `%@%` means the email contains an `@` anywhere. An empty email is counted as not valid.
- `bronze_api` means the API events after validation: the valid side of feature 004,
  through the shared view of feature 005. Reading bronze directly would skip the
  validation and the quarantine.
- `bronze_files` means `workspace.bronze.dados_files`, read through its boundary view. The
  files source has no rejection rules of its own yet, so it has no validation table or
  quarantine in this feature.
- "uuid" means the constitution's `md5` hash key, not a random UUID.
- Files users are not merged. On 2026-10-18 each employee appears in exactly one sales
  row, so the key is unique without deduplication. The first design deduplicated with
  `AUTO CDC` (SCD type 1). The owner replaced it with plain append flows as simpler and
  sufficient for the data; uniqueness is verified instead of enforced.
- API users are not deduplicated beyond the key. Because the key includes the access time,
  as requested, each visit is a separate user row.
- `empresa_usuario` is empty for API rows; site users have no company.
- The record source of the files is `ARQUIVO`, the constitution's value for that source.
- The earlier pipeline's description of `tb_usuario` (UNION of the two sources) is
  replaced: the constitution requires one flow per source.
- Sales, courses and gold are out of scope.
- All data is synthetic. The generator writes sex `X` for about 2% of users and an email
  without `@` (`#yahoo.com`, `#google.com`) for about 4%.
