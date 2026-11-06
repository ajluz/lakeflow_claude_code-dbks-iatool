# Feature Specification: Gold Sales Fact

**Feature Branch**: `013-gold-fato-venda`

**Created**: 2026-11-05

**Status**: Draft

**Input**: User description: "create a fact table called fato_venda where will have the follow fields: sk_tempo, sk_codigos, sk_curso, sk_usuario, valor_desconto, valor_pago. the source fact code will need to treat the Não se aplica rule when the origem is ARQUIVO."

## Clarifications

### Session 2026-11-05

- Q: Every sale (2024-06-01 to 2025-12-23) is older than the course versions, which start at the catalog's first change on 2026-10-11. Which version should a sale get? → A: The version in effect at the sale's time. If the sale predates the course's first version, it gets that first version (owner).
- Q: Should the course join keep only the current version (`__END_AT IS NULL`)? → A: No. The fact uses the version in effect at the sale's time, with the first-version fallback (owner). A current-only join would move past sales to a later version after an update, and would send a deleted course's sales to unknown.
- Q: The fact is processed incrementally (constitution v3.0.0), so a sale's keys are set once, when the sale is first processed. What happens to a sale whose dimension row did not exist yet? → A: It is not an issue: the fact is loaded only after all dimensions have finished loading in the same pipeline update, so a sale sees every dimension row of that update (owner). The only remaining case, a dimension row that arrives in a later update than its sale, keeps `-1`, and only a full refresh approved by the owner resolves it again.

### Session 2026-11-06

- Q: How should the fact treat sales that have no access row (200,000 file sales and 2,174 site sales whose access silver dropped)? → A: Keep them (owner). The sales drive the query, so only accesses that ended in a purchase are read (218,298 of 2,516,192 on 2026-11-06); an access without a sale never enters the fact. The access lookup stays a left join from the sales: a site sale whose access silver dropped gets the location `Desconhecido`, and a file sale is never looked up (`Não se aplica`).
- Q: Which of the fact's four dimension lookups should become inner joins? → A: All four (owner, following Kimball). The course rule gains a last fallback so that every sale finds a version: a sale with no version in effect that is not older than the first version gets the course's most recent version that started before it (for example the closed version of a deleted course). The owner noted that this is a demonstration and no new data will be generated for the past. Coverage measured on 2026-11-06: 0 sales without a match in each of the four dimensions. The `tb_acesso` lookup stays a left join (previous answer).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every sale in the fact, with its measures (Priority: P1)

As an analyst, I want `workspace.gold.fato_venda` to hold one row per sale with what was
paid and the discount given, so that revenue and discounts can be totalled and sliced by
date, course, user and sale codes.

**Why this priority**: it is the star schema's fact. Without it, the dimensions answer no
business question.

**Independent Test**: after a run, the fact has exactly as many rows as
`silver.tb_venda`, 420,472 on 2026-11-05. The totals of `valor_pago` and `valor_desconto`
equal silver's to the cent.

**Acceptance Scenarios**:

1. **Given** the sales in `silver.tb_venda`, **When** the run completes, **Then** the fact
   has one row per sale, none lost and none duplicated.
2. **Given** a sale, **When** its row is read, **Then** `valor_pago` and `valor_desconto`
   equal the sale's values in silver.
3. **Given** the whole fact, **When** the measures are summed, **Then** the totals equal
   silver's.

---

### User Story 2 - Every row points to a dimension row (Priority: P1)

As an analyst, I want every dimension key of every row to be filled and to exist in its
dimension, so that a join to any dimension never drops a sale.

**Why this priority**: the constitution requires facts to reconcile with silver, with no
null keys (Principles I and VII). The four dimension lookups are inner joins (owner,
2026-11-06), which the constitution allows only because each dimension covers every key a
sale can carry (Principle V). The earlier pipeline's inner join to the accesses silently
lost every file sale, so that lookup stays a left join.

**Independent Test**: for each of the four keys:
- no row has an empty key;
- every key exists in its dimension;
- joining the fact to all four dimensions returns all of its rows.

**Acceptance Scenarios**:

1. **Given** a sale whose date is in the calendar, **When** its row is read, **Then**
   `sk_tempo` is that day's key.
2. **Given** a sale whose user is in `dim_usuario`, **When** its row is read, **Then**
   `sk_usuario` is that user's key.
3. **Given** the sales of `silver.tb_venda`, **When** each is looked up in the four
   dimensions, **Then** every sale matches a row in each (0 without a match on
   2026-11-06), so the inner joins keep every sale.
4. **Given** a sale, **When** its course is looked up, **Then** `sk_curso` is the key of
   the course version that applies to the sale (FR-005), and some version always applies.
5. **Given** a sale that would match no row of a dimension, **When** the fact loads,
   **Then** the row-count check after the load shows the loss, and it is treated as a
   violation to fix in the dimension (constitution, Principle V).

---

### User Story 3 - Sale codes, with "Não se aplica" for file sales (Priority: P1)

As an analyst, I want each sale's origin, access location, payment method and discount
band resolved to its row of the junk dimension, with file sales marked as having no
access location, so that revenue can be sliced by channel and device.

**Why this priority**: the request names this rule explicitly. File sales (`ARQUIVO`) come
from corporate contracts and have no site access. Without the rule they either match no
code row or are dropped.

**Independent Test**: every file sale's `sk_codigos` points to a `dim_codigos` row with
`local_acesso = 'Não se aplica'`. Every site sale's code row has its access location, or
`Desconhecido` when its access is missing.

**Acceptance Scenarios**:

1. **Given** a sale with `origem = 'ARQUIVO'`, **When** its codes are resolved, **Then**
   the access location is `Não se aplica`, and the row's `sk_codigos` points to the
   matching `dim_codigos` row.
2. **Given** a site sale (`API`) whose access is in `silver.tb_acesso`, **When** its codes
   are resolved, **Then** the access location is that access's location.
3. **Given** a site sale whose access is not in `silver.tb_acesso` (2,174 on 2026-11-05),
   **When** its codes are resolved, **Then** the access location is `Desconhecido`, and
   the sale is kept.
4. **Given** a sale with an empty payment method or discount, **When** its codes are
   resolved, **Then** they follow `dim_codigos`'s rules: `Desconhecido` for the payment
   method, `Não se aplica` for the discount.

---

### Edge Cases

- **A sale date outside the calendar** (before 2021 or after 2030): the inner join would
  drop it. None exists (sales run from 2024-06-01 to 2025-12-23), and the demonstration
  generates no new data for the past; the row-count check would show it, and the calendar
  would be extended.
- **A dimension row that arrives after its sale.** Within one pipeline update the
  dimensions finish loading before the fact, so a sale sees them. Every sale's user is in
  `dim_usuario` since 2026-11-06, because silver no longer drops users.
- **A sale with no access row** (2,174 site sales on 2026-11-06, whose event silver dropped
  for the address): location `Desconhecido` in the codes, kept in the fact.
- **An access that did not end in a purchase**: never read. The lookup starts from the sales,
  so only the accesses of sales are used.
- **A file sale**: it has no access by nature. Its location is `Não se aplica` and it is
  never looked up in the accesses.
- **A course deleted at the live demo**: its sales keep their course key. The deletion only
  closes the last version, and every sale predates the deletion (FR-005). A sale dated
  after the deletion would get that closed version, the most recent one that started
  before it, so the inner join keeps it.
- **A course updated at the live demo**: its past sales stay on the first version, the
  `247.00` price. Only sales after the update would get the new version (FR-005).
- **Every sale predates the course versions.** Sales run from 2024-06-01 to 2025-12-23.
  The course versions start at the catalog's first change time, 2026-10-11, so no sale
  falls inside a version's validity period. Such a sale gets its course's first version
  (FR-005).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a gold fact `workspace.gold.fato_venda` built from
  the sales in `workspace.silver.tb_venda`.
- **FR-002**: The fact MUST have exactly these columns:

  | Column | Type | Meaning |
  |---|---|---|
  | `sk_tempo` | BIGINT | key of the sale's day in `dim_tempo` |
  | `sk_codigos` | BIGINT | key of the sale's code combination in `dim_codigos` |
  | `sk_curso` | BIGINT | key of the sale's course version in `dim_curso` |
  | `sk_usuario` | BIGINT | key of the sale's user in `dim_usuario` |
  | `valor_desconto` | DECIMAL(9,2) | discount given, as in silver; additive |
  | `valor_pago` | DECIMAL(9,2) | amount paid, as in silver; additive |

- **FR-003**: Grain: one row per sale of `silver.tb_venda`. The row count MUST equal
  silver's, and no sale may be excluded.
- **FR-004**: Every dimension key MUST be filled and MUST exist in its dimension. The four
  dimension lookups MUST be inner joins (owner, 2026-11-06), each with its coverage
  guaranteed and verified by an anti join of `silver.tb_venda` against the dimension that
  returns 0 rows (constitution, Principle V):
  - `dim_tempo`: the calendar covers 2021–2030, and every sale falls between 2024-06-01
    and 2025-12-23;
  - `dim_codigos`: it holds every combination of the four codes computed with its own rules
    (FR-008);
  - `dim_curso`: every sale's course has at least one version, and FR-005 always picks one;
  - `dim_usuario`: users come from the same sources as sales, and silver drops no user since
    2026-11-06.

  No key uses `-1` or `-2`; the members stay in the dimensions for other facts.
- **FR-005**: `sk_curso` MUST be the key of the version of the sale's course (by
  `curso_uuid`, excluding members) in effect at the sale's time: the version whose
  `__START_AT` ≤ `data_venda` < `__END_AT`, an open `__END_AT` counting as infinite. When the
  sale is older than the course's first version, it MUST get that first version (the
  earliest `__START_AT`). Otherwise (a sale dated after a deletion, or in a gap between
  versions), it MUST get the most recent version whose `__START_AT` ≤ `data_venda`. A
  course with no version at all is not possible, because the coverage check of FR-004
  requires every sale's course in `dim_curso`. A course that was updated or deleted later
  keeps its sales on the version that applied to them. The lookup
  MUST NOT be restricted to the current version (`__END_AT IS NULL`).
- **FR-006**: `sk_tempo` MUST be the key of the `dim_tempo` row whose date is the sale's
  date (the day of `data_venda`).
- **FR-007**: `sk_usuario` MUST be the key of the `dim_usuario` row with the sale's
  `usuario_uuid`.
- **FR-008**: `sk_codigos` MUST be the key of the `dim_codigos` row matching all four of
  the sale's codes, computed with `dim_codigos`'s rules:
  - origin: the sale's `origem`;
  - access location: `Não se aplica` when the origin is `ARQUIVO`; otherwise the location
    of the sale's access in `silver.tb_acesso`, or `Desconhecido` when there is none;
  - payment method: the sale's `forma_pagamento`, `Desconhecido` when empty;
  - discount: the sale's `percentual_desconto`, `Não se aplica` when empty.
- **FR-009**: The access location MUST be looked up from the sales, so that only accesses
  that ended in a purchase are read. It is a left join from the sales to `silver.tb_acesso`
  for site sales only, and it MUST NOT remove sales: a site sale with no access row (2,174
  on 2026-11-06) and every file sale stay in the fact (owner, 2026-11-06).
- **FR-010**: The fact MUST hold only surrogate keys and the two measures. No descriptive
  attribute, and no silver key, is stored.
- **FR-011**: The fact MUST NOT declare expectations: this spec requests none
  (constitution v2.0.0, Principle III). Keys and reconciliation MUST be verified by query.
- **FR-012**: The fact MUST carry `quality` = `gold`, and MUST read only silver and gold
  datasets.
- **FR-013**: The fact's grain, measures (both additive), key resolution and members MUST be
  documented in `doc/pipeline-reference.md` before it is built. The documentation replaces
  the earlier pipeline's description.

### Key Entities

- **Sale fact row**: one sale, with four dimension keys and two additive measures.
- **Sale codes**: the sale's origin, access location, payment method and discount band,
  resolved together to one row of the junk dimension.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Rows in `fato_venda` = rows in `silver.tb_venda`, with a difference of 0
  (420,472 on 2026-11-05).
- **SC-002**: `sum(valor_pago)` and `sum(valor_desconto)` equal silver's, with a difference
  of 0.00.
- **SC-003**: 0 rows have an empty key. 100% of each key's values exist in its dimension.
  Joining the fact to all four dimensions returns 100% of its rows.
- **SC-004**: 100% of the 200,000 file sales have a code row with
  `local_acesso = 'Não se aplica'`. 0 site sales do.
- **SC-005**: 0 rows have a key below 0 in any of the four keys. `sk_codigos` uses
  `Desconhecido` as the location for exactly the site sales with no access (2,174 on
  2026-11-06).
- **SC-006**: Before the inner joins are accepted, the anti join of `silver.tb_venda`
  against each of the four dimensions returns 0 rows. On 2026-11-06 every sale points to
  its course's only version, through the first-version fallback.

## Assumptions

- **Each sale is processed once.** The fact takes new sales incrementally, and its keys are
  resolved when the sale is processed, after the dimensions of the same update have loaded
  (owner, 2026-11-05; constitution v3.0.0, Principle V). Later dimension changes do not
  rewrite sales already in the fact. That matches FR-005: past sales stay on the course
  version that applied to them.

- **Source**: `silver.tb_venda` for sales and measures; `silver.tb_acesso` only for the
  access location of site sales; the four gold dimensions for the keys.
- **"The Não se aplica rule when the origem is ARQUIVO"** means the access location used to
  find the sale's code row. It is `dim_codigos`'s own rule, applied to the sale, as the
  earlier pipeline did.
- **Inner joins only where coverage is guaranteed.** The four dimension lookups are inner
  joins (owner, 2026-11-06; constitution v3.1.0, Principle V). The access lookup stays a
  left join: the earlier pipeline's inner join to the accesses removed every file sale.
- **This is a demonstration.** No new data will be generated for the past (owner,
  2026-11-06), so no sale can fall outside the calendar, and the coverage measured on
  2026-11-06 holds for the existing sales.
- **Exactly the six requested columns.** No degenerate key (such as `venda_uuid`) and no
  `data_carga` are added. The request lists none, and the other features followed the
  requested lists.
- **Measures**: `valor_pago` and `valor_desconto` come from silver unchanged; both are
  additive.
- **Dimensions are not changed** by this feature.
- `obt_acesso` is out of scope.
- All data is synthetic.
