# Feature Specification: Gold Access One-Big-Table

**Feature Branch**: `014-gold-obt-acesso`

**Created**: 2026-11-06

**Status**: Draft

**Input**: User description: "create a obt table called obt_acesso with the follow columns: local_acesso, endereco_ip_acesso, data, ano, mes, mes_ano, dia_mes, dia_semana, dia_semana_int, fl_dia_semana, dia_ano, fl_ultimo_dia_mes, semana_ano, semestre, trimestre, bimestre, qtde_acesso, qtde_usuario, qtde_vendidos."

## Clarifications

### Session 2026-11-06

- Q: Is a row one access, or one combination of device location, address and day? → A: One combination of device location, address and day (owner). The three counts are summed over that combination's accesses (2,516,058 rows on 2026-11-06, 134 fewer than accesses).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Site accesses by device and calendar, without joins (Priority: P1)

As an analyst, I want one table that holds the site's accesses with their device location,
address and every calendar attribute of the access day, so that I can count accesses by
day, week, month or weekday, and by device, without joining any other table.

**Why this priority**: it is the table's reason to exist. A one-big-table is a
denormalized convenience for one analysis, here the access funnel; without the access
counts by calendar and device, nothing else in it is useful.

**Independent Test**: after a run, the sum of `qtde_acesso` equals the number of accesses
in the conformed access table (2,516,192 on 2026-11-06), and the sum per `local_acesso` and
per `data` equals the same counts computed directly from that table.

**Acceptance Scenarios**:

1. **Given** the conformed site accesses, **When** the run completes, **Then** every access
   is counted exactly once in `qtde_acesso`, none lost and none counted twice.
2. **Given** an access on a given day, **When** its row is read, **Then** `data` is that
   day and the calendar columns (`ano`, `mes`, `mes_ano`, `dia_mes`, `dia_semana`,
   `dia_semana_int`, `fl_dia_semana`, `dia_ano`, `fl_ultimo_dia_mes`, `semana_ano`,
   `semestre`, `trimestre`, `bimestre`) equal the calendar dimension's values for that day.
3. **Given** an access whose device is not recognised, **When** its row is read, **Then**
   `local_acesso` is `unknown`, as in the conformed access table, and the access is still
   counted.

---

### User Story 2 - Identified users among the accesses (Priority: P1)

As an analyst, I want to know how many accesses came from an identified user, so that I can
measure how much of the audience is known.

**Why this priority**: the share of identified users is the second step of the funnel.

**Independent Test**: after a run, the sum of `qtde_usuario` equals the number of accesses
that carry a user in the conformed access table (748,571 on 2026-11-06).

**Acceptance Scenarios**:

1. **Given** an access that carries a user, **When** it is counted, **Then** it adds 1 to
   `qtde_usuario`.
2. **Given** an access without a user, **When** it is counted, **Then** it adds 0 to
   `qtde_usuario`, and it still adds 1 to `qtde_acesso`.

---

### User Story 3 - Accesses that ended in a sale (Priority: P1)

As an analyst, I want to know how many accesses ended in a purchase, so that I can measure
the conversion from access to sale by device and by day.

**Why this priority**: conversion is the last step of the funnel and the main question the
table answers.

**Independent Test**: after a run, the sum of `qtde_vendidos` equals the number of site
sales linked to an access in the conformed sales table (218,298 on 2026-11-06).

**Acceptance Scenarios**:

1. **Given** an access linked to a sale, **When** it is counted, **Then** it adds the
   number of its sales to `qtde_vendidos` (1 for every access on 2026-11-06).
2. **Given** an access with no sale, **When** it is counted, **Then** it adds 0 to
   `qtde_vendidos`, and the access is still counted.
3. **Given** a sale with no access (file sales, and site sales whose access was rejected
   by silver), **When** the table is built, **Then** it contributes nothing: the table
   counts accesses, not sales.

---

### Edge Cases

- **An access whose address was impossible** (`999.999.999.999`): silver removed it from
  the conformed access table (a declared exclusion), so it is not in this table either.
- **Two accesses with the same device, address and day**: they share one row, and that
  row's `qtde_acesso` counts both (FR-002). On 2026-11-06 there were 134 fewer combinations
  than accesses.
- **An access date outside the calendar** (before 2021 or after 2030): it would have no
  calendar attributes. None exists: accesses run from 2024-06-01 to 2024-06-03.
- **An access with no recognised device**: kept, with `local_acesso = 'unknown'` (117,131
  accesses at the last count of the access table).
- **A sale linked to an access more than once**: not possible today; each access matched
  at most one sale on 2026-11-06. If it happened, the access would still be counted once
  in `qtde_acesso`, and every sale would count in `qtde_vendidos`.
- **New accesses or sales arrive**: the table reflects them after the next run.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a gold one-big-table `workspace.gold.obt_acesso`
  about the site's accesses.
- **FR-002**: Grain: one row per combination of `local_acesso`, `endereco_ip_acesso` and
  `data` (owner, 2026-11-06). The three counts are summed over the accesses of that
  combination. No two rows share the same combination (2,516,058 rows on 2026-11-06).
- **FR-003**: The table MUST have exactly these columns, in this order: `local_acesso`,
  `endereco_ip_acesso`, `data`, `ano`, `mes`, `mes_ano`, `dia_mes`, `dia_semana`,
  `dia_semana_int`, `fl_dia_semana`, `dia_ano`, `fl_ultimo_dia_mes`, `semana_ano`,
  `semestre`, `trimestre`, `bimestre`, `qtde_acesso`, `qtde_usuario`, `qtde_vendidos`.
- **FR-004**: `local_acesso` and `endereco_ip_acesso` MUST be the access's values in the
  conformed access table, unchanged.
- **FR-005**: `data` MUST be the day of the access, and the 13 calendar columns MUST be
  the calendar dimension's attributes for that day, with the same names, values and
  types.
- **FR-006**: `qtde_acesso` MUST count accesses: its sum over the whole table equals the
  number of accesses in the conformed access table.
- **FR-007**: `qtde_usuario` MUST count accesses that carry a user.
- **FR-008**: `qtde_vendidos` MUST count the site sales linked to the accesses, through
  the access identifier of the conformed sales table. Linking to sales MUST NOT remove or
  duplicate accesses in `qtde_acesso`.
- **FR-009**: Every access of the conformed access table MUST be counted. No access may
  be lost because of the calendar or the sales lookup.
- **FR-010**: The three counts MUST be additive: summing them over any set of rows gives
  the counts for that set.
- **FR-011**: The table MUST read only silver and gold datasets, MUST carry
  `quality` = `gold`, and MUST be recomputed from its sources on every run.
- **FR-012**: The table MUST NOT declare expectations: this spec requests none. Its
  counts MUST be verified by query against the sources.
- **FR-013**: The table's grain, its source datasets and the meaning of each count MUST
  be described in the project documentation before it is built, replacing the earlier
  pipeline's description.

### Key Entities

- **Access row**: one combination of device location, address and day (FR-002), with the
  day's calendar attributes and the three counts of its accesses.
- **Access**: one visit to the site, from the conformed access table. It may carry a user
  and may be linked to a sale.
- **Calendar day**: the calendar dimension's row for the access's day.
- **Site sale**: a sale of the conformed sales table that references an access.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The sum of `qtde_acesso` equals the conformed access table's row count, with
  a difference of 0 (2,516,192 on 2026-11-06).
- **SC-002**: The sum of `qtde_usuario` equals the accesses that carry a user, with a
  difference of 0 (748,571 on 2026-11-06).
- **SC-003**: The sum of `qtde_vendidos` equals the site sales linked to an access, with a
  difference of 0 (218,298 on 2026-11-06).
- **SC-004**: For 100% of rows, the 13 calendar columns equal the calendar dimension's
  values for `data`, and 0 rows have an empty `data`.
- **SC-005**: Summed per `local_acesso` and per `data`, the three counts equal the same
  counts computed directly from the sources (3 locations and 3 days on 2026-11-06).
- **SC-006**: The table has exactly the 19 requested columns, in the requested order.
- **SC-007**: No two rows share the same `local_acesso`, `endereco_ip_acesso` and `data`,
  and every row has `qtde_acesso` ≥ 1.

## Assumptions

- **"obt"** means the constitution's one-big-table (`obt_`): a denormalized convenience
  for one analysis, with a stated grain. The business measures stay defined in their own
  datasets: accesses in the conformed access table, sales in the sales fact.
- **Sources**: the conformed access table (`silver.tb_acesso`) for the accesses, the
  calendar dimension (`gold.dim_tempo`) for the calendar attributes, and the conformed
  sales table (`silver.tb_venda`) for the link to sales, through its access identifier.
  The sales fact cannot be used for the link: it stores no access identifier.
- **Calendar names**: the column names are the calendar dimension's own (`mes` is the
  Portuguese month name, `mes_ano` the month number, `dia_semana_int` 1 = Sunday …
  7 = Saturday), as in the earlier pipeline.
- **`qtde_vendidos`** counts sales, not distinct accesses with a sale. On 2026-11-06 the two
  are equal, because each access matched at most one sale.
- **Only site accesses**: file sales have no access, so they are outside this table.
- **The earlier pipeline's `obt_acesso`** (a left join of every access to the sales) is
  replaced. Its description in the project documentation still points to a file that no
  longer exists.
- **No surrogate keys**: a one-big-table carries attributes, not dimension keys.
- All data is synthetic.
