# Feature Specification: Gold Junk Dimension of Sale Codes

**Feature Branch**: `011-gold-dim-codigos`

**Created**: 2026-11-05

**Status**: Draft

**Input**: User description: "create the dim_codigos that will be a junk dimension with the follow fields: sk_codigos BIGINT IDENTITY, origem_usuario STRING, local_acesso STRING, forma_pagamento STRING, percentual_disconto STRING, data_carga TIMESTAMP. the fields will have as origem the tb_venda and tb_acesso. If the origem_usuario is iguals to ARQUIVO, return Não se aplica. if the percentual_disconto is null, return Não se aplica as well."

## Clarifications

### Session 2026-11-05

- Q: The request asks for an identity key, which the pipeline's materialized views and
  `AUTO CDC` targets do not support, and a script outside the pipeline is allowed only for
  static data. How is `sk_codigos` produced? → A: A deterministic key computed from the
  combination's four codes inside the pipeline, as `dim_usuario` does; no identity column
  (owner).
- Q: What does `data_carga` mean for a dimension that the pipeline recomputes? → A: The
  time of the pipeline update that last wrote the row, as for `dim_usuario`; never
  silver's load time. Recorded during planning (research, Decision 6).
- Q: Should the dimension hold only the combinations that some sale has, or every possible
  combination? → A: Every possible combination: a cross join of the values each code takes,
  so that any combination a future sale brings already has a row (owner, during
  `/speckit-plan`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One row per combination of sale codes (Priority: P1)

As an analyst, I want `workspace.gold.dim_codigos` to hold every possible combination of a
sale's low-cardinality codes (where the buyer came from, the device of the access, the
payment method and the discount), one row each, so that sales can be sliced by these
codes through a single key instead of four columns on the fact.

**Why this priority**: the constitution groups low-cardinality flags and codes that belong
to no other dimension into a junk dimension named `dim_codigos` (Principle VII), and
`fato_venda` needs it to hold only keys and measures.

**Independent Test**: after a load, the dimension holds exactly the cross product of the
values each code takes (after the rules of FR-002), one row each with its own surrogate
key, and every silver sale finds its row.

**Acceptance Scenarios**:

1. **Given** a site sale (`origem = 'API'`) whose access is in `silver.tb_acesso`,
   **When** the dimension is read, **Then** one row has that sale's origin, the access's
   `local_acesso` (`Mobile`, `Computador` or `unknown`), its payment method and its
   discount.
2. **Given** a corporate sale (`origem = 'ARQUIVO'`), **When** the dimension is read,
   **Then** its combination has `local_acesso` = `Não se aplica`, because file sales have
   no access.
3. **Given** a sale whose discount is empty, **When** the dimension is read, **Then** its
   combination has `percentual_desconto` = `Não se aplica`.
4. **Given** a site sale whose access is not in `silver.tb_acesso` (2,174 sales on
   2026-11-05), **When** the dimension is read, **Then** its combination has
   `local_acesso` = `Desconhecido`.
5. **Given** two sales with the same four codes, **When** the dimension is read, **Then**
   they share one row.
6. **Given** a combination of existing code values that no sale has yet (for example a
   site sale paid by `boleto` from a `Computador`), **When** the dimension is read,
   **Then** it already has a row.

---

### User Story 2 - Surrogate keys that never change (Priority: P1)

As an analyst, I want each combination's surrogate key to keep its value across every
load, so that sales facts built on it stay correct.

**Why this priority**: facts reference dimensions only through surrogate keys, and a key
that is reassigned silently breaks every fact row that points to it (Principle VII). The
earlier pipeline's `dim_codigos` was exposed to this (`doc/known-issues.md`).

**Independent Test**: record every `(combination, sk_codigos)` pair, load again with and
without new combinations, and compare: every recorded pair is unchanged.

**Acceptance Scenarios**:

1. **Given** a combination's `sk_codigos`, **When** a later load runs with no new data,
   **Then** the key is the same.
2. **Given** new sales that bring a code value not seen before (for example a new payment
   method), **When** the next load runs, **Then** every combination with that value gets a
   key no other row has, and every existing key is unchanged.

---

### User Story 3 - Explicit members for unknown and not-applicable codes (Priority: P2)

As an analyst, I want the dimension to contain an "unknown" row and a "not applicable"
row, so that a fact whose codes are missing or do not apply still points to a row.

**Why this priority**: the constitution requires these members in every dimension. Every
sale has codes today, so the members are a safety net rather than a daily need.

**Independent Test**: the dimension has exactly one row with key `-1` and one with key
`-2`, each with its label in every code column.

**Acceptance Scenarios**:

1. **Given** the dimension, **When** it is read, **Then** it contains `-1` with
   `Desconhecido` and `-2` with `Não se aplica` in all four code columns, in addition to
   the combinations.
2. **Given** later loads, **When** the members are read, **Then** there is still exactly
   one of each, with the same keys.

---

### Edge Cases

- **A member's label equals a real combination's value.** `local_acesso` = `Não se aplica`
  appears in real combinations (file sales) and in member `-2`. They stay distinct rows,
  because a real combination's `origem_usuario` is always `API` or `ARQUIVO`.
- **Combinations that cannot occur.** A file sale never has an access, so the cross product
  gives `ARQUIVO` only `local_acesso` = `Não se aplica`, and gives `API` never
  `Não se aplica`. Other unlikely pairs (such as a file sale paid by `boleto`) are kept:
  they are possible values, and the dimension does not guess which pairs the sources will
  produce.
- **`unknown` versus `Desconhecido`.** `unknown` is the access location silver assigns to
  an unrecognised device; `Desconhecido` means the sale has no access row. They are kept
  apart, as two different facts about the sale.
- **An empty payment method.** None today. If one appears, its combination carries
  `Desconhecido`, so that every combination can be matched by value.
- **A code value stops appearing.** Silver is append-only, so a value once seen is never
  withdrawn; its rows are kept.
- **A brand-new code value** (for example a new payment method). It is crossed with every
  other code's values, adding new rows with new keys; nothing existing changes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide the gold junk dimension `workspace.gold.dim_codigos`,
  built from `workspace.silver.tb_venda` and `workspace.silver.tb_acesso`.
- **FR-002**: The dimension MUST have exactly these columns, in this order:

  | Column | Type | Meaning |
  |---|---|---|
  | `sk_codigos` | BIGINT | surrogate key |
  | `origem_usuario` | STRING | where the sale came from: `API` (site) or `ARQUIVO` (corporate file), the sale's `origem` |
  | `local_acesso` | STRING | device of the access that led to the sale; `Não se aplica` for `ARQUIVO`; `Desconhecido` when the access is missing |
  | `forma_pagamento` | STRING | payment method |
  | `percentual_desconto` | STRING | discount, as in silver (`0%`, `5%`, `10%`, `15%`); `Não se aplica` when empty |
  | `data_carga` | TIMESTAMP | time of the pipeline update that last wrote the row; never silver's `data_carga` |

- **FR-003**: The dimension MUST hold one row per combination in the cross product of the
  values each code takes, after the rules of FR-002, plus the two members of FR-006. Its
  grain is one combination. The values of each code are:
  - `origem_usuario`: the distinct `origem` of the sales;
  - `local_acesso`: the distinct `local_acesso` of the accesses, plus `Desconhecido`;
    `Não se aplica` replaces them when `origem_usuario` is `ARQUIVO`;
  - `forma_pagamento` and `percentual_desconto`: their distinct values among the sales,
    with the empty-value labels of FR-002.

  The cross product MUST be taken over these value lists, never over the rows of the two
  tables, so that its size depends on the number of values, not on the number of sales
  and accesses.
- **FR-004**: `sk_codigos` MUST be a single column, unique and never empty, and MUST keep
  its value for a given combination across every load. A mechanism that can reassign keys
  MUST NOT be used. Real combinations' keys MUST be positive.
- **FR-005**: The dimension MUST be built by the pipeline, and `sk_codigos` MUST be
  computed deterministically from the combination's four codes, the same way on every
  update, as `dim_usuario` computes its key (Clarifications). It is not an identity
  column. The same combination therefore always gets the same key, even if the dimension
  is fully recomputed.
- **FR-006**: The dimension MUST contain two members: `-1` with `Desconhecido` and `-2`
  with `Não se aplica` in all four code columns.
- **FR-007**: The dimension MUST be SCD type 1. A row is the combination itself, so its
  attributes never change; no history is kept.
- **FR-008**: A code value that appears in silver for the first time MUST be in the
  dimension, in every combination, after the next pipeline update, with new keys; no
  separate script has to be run.
- **FR-009**: The dimension MUST carry `quality` = `gold` and MUST NOT reference another
  dimension.
- **FR-010**: The dimension MUST NOT declare expectations; this spec requests none
  (constitution v2.0.0, Principle III). Uniqueness of the key and of the combination MUST
  be verified by query.
- **FR-011**: The project documentation MUST describe the dimension, its sources, grain,
  rules, members, key and SCD type, replacing the earlier pipeline's description, and the
  known issue about the earlier cross join of the two tables MUST be closed.

### Key Entities

- **Code combination**: one distinct set of origin, access location, payment method and
  discount found among the sales, with its surrogate key.
- **Default member**: the "unknown" or "not applicable" row that facts point to when
  codes are missing or do not apply.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Rows in `dim_codigos` = the cross product of the code values + 2 members. On
  2026-11-05: `API` 4 locations × 3 payment methods × 4 discounts = 48, `ARQUIVO` 1 × 3 ×
  4 = 12, total 60 + 2 = 62.
- **SC-002**: 0 rows have an empty key or an empty code column; no two rows share a key;
  no two rows share all four codes.
- **SC-003**: 100% of the 420,472 silver sales (2026-11-05) match exactly one combination
  row by their four codes.
- **SC-004**: After a load with no new data, and after a full refresh of the dimension,
  100% of previously recorded `(combination, sk_codigos)` pairs are unchanged, including
  the members'.
- **SC-005**: Exactly 1 `-1` row and 1 `-2` row exist.
- **SC-006**: 100% of `ARQUIVO` combinations have `local_acesso` = `Não se aplica`, and no
  `API` combination does.

## Assumptions

- **"If origem_usuario is ARQUIVO, return Não se aplica"** applies to `local_acesso`, not
  to `origem_usuario` itself. File sales have no access, so their access location does not
  apply; replacing the origin would erase the one code that tells the two sources apart.
  The earlier pipeline's `dim_codigos` applied the rule the same way.
- **Discount column name.** The request writes `percentual_disconto`; silver's column is
  `percentual_desconto`, and Portuguese spelling is *desconto*. The dimension uses
  `percentual_desconto`, so facts match on the same name. `disconto` survives only in the
  source files' raw field names.
- **Empty discount.** Silver writes `0%` when a sale has no discount, so no discount is
  empty today and the `Não se aplica` rule is a safeguard.
- **Missing access.** The request does not say what a site sale with no access row gets;
  `Desconhecido` is used, the project's label for an unknown value.
- **Combination values are taken as silver delivers them**, including `unknown` for an
  unrecognised device; the dimension does not reclassify them.
- **`Desconhecido` is always a location value**, even if every site sale someday has an
  access row, so the list of values does not depend on a join result.
- **22 of the 60 combinations are used by sales today** (2026-11-05); the other 38 are
  possible and ready for future sales.
- **Key collisions.** A deterministic key of 64 bits over a few dozen combinations makes a
  collision practically impossible; uniqueness is still verified by query (FR-010).
- **Out of scope**: `fato_venda` and `obt_acesso`, which will use this dimension; adding
  other codes (such as installments) to it; changing silver.
