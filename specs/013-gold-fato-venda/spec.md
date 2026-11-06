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
null keys, and with unmatched lookups resolved to an explicit member (Principles I and VII).
The earlier pipeline joined with inner joins and silently lost every file sale, which have no
access.

**Independent Test**: for each of the four keys:
- no row has an empty key;
- every key exists in its dimension;
- joining the fact to all four dimensions returns all of its rows.

**Acceptance Scenarios**:

1. **Given** a sale whose date is in the calendar, **When** its row is read, **Then**
   `sk_tempo` is that day's key.
2. **Given** a sale whose user is in `dim_usuario`, **When** its row is read, **Then**
   `sk_usuario` is that user's key.
3. **Given** a sale whose user is not in `dim_usuario` (4,362 on 2026-11-05, rejected by
   silver's user rules), **When** its row is read, **Then** `sk_usuario` is `-1` (unknown).
4. **Given** a sale, **When** its course is looked up, **Then** `sk_curso` is the key of
   the course version that applies to the sale (FR-005).
5. **Given** any lookup with no match, **When** the row is read, **Then** the key is `-1`,
   and the row is still in the fact.

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

- **A sale date outside the calendar** (before 2021 or after 2030): `sk_tempo` = `-1`.
  None exists on 2026-11-05.
- **A dimension row that arrives after its sale.** Within one pipeline update the
  dimensions finish loading before the fact, so a sale sees them. A dimension row that only
  arrives in a later update does not change sales already written. They keep `-1` until a
  full refresh approved by the owner. The 4,362 sales whose user silver rejects keep `-1`
  in any case.
- **A sale with no access row** (site sales whose event was dropped by silver): location
  `Desconhecido` in the codes, kept in the fact.
- **A file sale**: it has no access by nature. Its location is `Não se aplica` and it is
  never looked up in the accesses.
- **A course deleted at the live demo**: its sales keep their course key. The deletion only
  closes the last version, and every sale predates the deletion (FR-005).
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
- **FR-004**: Every dimension key MUST be filled and MUST exist in its dimension. A lookup
  with no match MUST resolve to `-1` (unknown). A dimension that does not apply to a sale
  by nature MUST resolve to `-2` (not applicable); no such case exists among the four keys
  today.
- **FR-005**: `sk_curso` MUST be the key of the version of the sale's course (by
  `curso_uuid`, excluding members) in effect at the sale's time: the version whose
  `__START_AT` ≤ `data_venda` < `__END_AT`, an open `__END_AT` counting as infinite. When the
  sale is older than the course's first version, it MUST get that first version (the
  earliest `__START_AT`). When the course has no version at all, `-1`. A course that was
  updated or deleted later keeps its sales on the version that applied to them. The lookup
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
- **FR-009**: Looking up the access location MUST NOT remove sales: a sale with no access,
  and every file sale, stays in the fact.
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
- **SC-005**: `sk_usuario = -1` for exactly the sales whose user is not in `dim_usuario`
  (4,362 on 2026-11-05). `sk_codigos` uses `Desconhecido` as the location for exactly the
  site sales with no access (2,174).
- **SC-006**: `sk_tempo = -1` for 0 sales on 2026-11-05. `sk_curso = -1` for 0 sales,
  because every sale's course has a version. On 2026-11-05 every sale points to its course's
  only version, through the first-version fallback.

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
- **No inner joins that drop sales.** The earlier pipeline's joins removed every file sale,
  because its access join required an access. The constitution forbids this (Principle I),
  so every lookup keeps the sale and falls back to a member.
- **Exactly the six requested columns.** No degenerate key (such as `venda_uuid`) and no
  `data_carga` are added. The request lists none, and the other features followed the
  requested lists.
- **Measures**: `valor_pago` and `valor_desconto` come from silver unchanged; both are
  additive.
- **Dimensions are not changed** by this feature.
- `obt_acesso` is out of scope.
- All data is synthetic.
