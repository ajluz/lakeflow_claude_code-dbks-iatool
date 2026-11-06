# Feature Specification: Gold User Dimension

**Feature Branch**: `009-gold-dim-usuario`

**Created**: 2026-10-28

**Status**: Draft

**Input**: User description: "create the gold dimension dim_usuario with the follow fields: 1. sk_usuario, 2. usuario_uuid, 3. nome_usuario, 4. email_usuario, 5. idade_usuario, 6. sexo_usuario, 7. estado_usuario, 8. profissao_usuario, 9. empresa_usuario, 10. origem, 11. dt_carga no scd type 2 is needed."

## Clarifications

### Session 2026-10-28

- Q: Should the dimension carry silver's `data_carga`, or a load time of its own? → A: Not silver's. Silver's `data_carga` is not a column of the dimension; the dimension has its own `data_carga`, the time the row entered the gold load job (owner).
- Q: When a user who is already in the dimension is processed again by a later pipeline update, should their `data_carga` change to that update's time, or keep the time they first entered the dimension? → A: A. It changes: every row gets the time of the latest update that rebuilt it, so `data_carga` shows when the dimension was last refreshed. *(Superseded on 2026-11-04, below.)*

### Session 2026-11-04

- Q: Should the dimension stay a materialized view? → A: No. The owner directed that it be rebuilt as a streaming table fed by an `AUTO CDC` flow stored as SCD type 1.
- Q: The owner asked for an identity surrogate key. Identity columns are not supported on `AUTO CDC` targets, so how does the dimension get its key? → A: A deterministic key computed before the flow, `xxhash64(usuario_uuid) & 9223372036854775807`. The owner asked for the best solution given that limitation, and proceeded with this one. Real keys are non-negative, so negative keys mean only the two members.
- Q: `AUTO CDC` rewrites only the rows that change, so what does `data_carga` mean now? → A: The time gold last wrote the row. It does not move on an update with no new data.
- Q: Should the dimension declare expectations? → A: No. The owner amended the constitution to v2.0.0, under which an expectation exists only when a spec requests it, and this spec does not request any.
- Q: How do the members get in? → A: Through their own one-time `AUTO CDC ... FROM SNAPSHOT` flow, so that the flow view stays a plain `SELECT` (owner: make the feature simpler).
- Q: The request said "all dimensions". Which does this feature cover? → A: `dim_usuario` only. `dim_curso` and `dim_codigos` are decided in their own features.

### Session 2026-11-05

- Q: Which users that silver rejected should get an inferred row in `dim_usuario` (a placeholder row keyed like any other user, so a fact's inner join always finds it)? → A: Only users referenced by sales (`silver.tb_venda`) but missing from `silver.tb_usuario`, 4,362 on 2026-11-05. Users seen only in accesses get none (owner).
- Q: What do an inferred user's descriptive columns hold? → A: `Desconhecido` in every text attribute (`nome_usuario`, `email_usuario`, `sexo_usuario`, `estado_usuario`, `profissao_usuario`, `empresa_usuario`), an empty `idade_usuario`, and `origem` set to the source that referenced the user (`API` for all 4,362 today) (owner).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One dimension row per user (Priority: P1)

As an analyst, I want `workspace.gold.dim_usuario` to describe every user known to silver,
one row each, with a surrogate key, so that sales and accesses can be sliced by user
attributes such as state, profession, sex, age and company.

**Why this priority**: it is the first gold dataset and the user side of the star schema
that `fato_venda` will join.

**Independent Test**: after a run, every `usuario_uuid` of `silver.tb_usuario` appears
exactly once in `dim_usuario`, with the same attributes and a surrogate key.

**Acceptance Scenarios**:

1. **Given** a user in `silver.tb_usuario`, **When** the run completes, **Then**
   `dim_usuario` has one row with that `usuario_uuid`, a surrogate key `sk_usuario`, and
   the user's name, email, age, sex, state, profession, company and record source as in
   silver.
2. **Given** a site user (`origem = 'API'`), **When** the row is read, **Then**
   `empresa_usuario` is empty, as in silver.
3. **Given** a corporate user (`origem = 'ARQUIVO'`), **When** the row is read, **Then**
   `empresa_usuario` holds the company.

---

### User Story 2 - Surrogate keys that never change (Priority: P1)

As an analyst, I want each user's surrogate key to keep its value across every pipeline
update, so that facts built on it stay correct.

**Why this priority**: facts reference dimensions only through surrogate keys
(constitution, Principle VII). A key that changes on refresh silently breaks every fact
row that points to it; the earlier pipeline was exposed to this (`doc/known-issues.md`).

**Independent Test**: record the surrogate keys of a sample of users, run another update
(with or without new users), and compare: every recorded key is unchanged.

**Acceptance Scenarios**:

1. **Given** a user's `sk_usuario`, **When** a later update runs with no new data,
   **Then** the user's `sk_usuario` is the same.
2. **Given** a user's `sk_usuario`, **When** a later update adds new users, **Then** the
   existing user's `sk_usuario` is the same, and each new user gets a key no other row
   has.
3. **Given** the whole dimension, **When** keys are counted, **Then** no two rows share
   an `sk_usuario`.

---

### User Story 3 - Explicit members for unknown and not-applicable users (Priority: P1)

As an analyst, I want the dimension to contain an "unknown" user and a "not applicable"
user, so that a fact whose user is missing or does not apply still points to a row and no
fact row is lost in a join.

**Why this priority**: the constitution requires these members, and the data needs them
today: 4,362 users referenced by sales are not in silver (their sex failed the user
rule), and 1,767,621 accesses have no user at all.

**Independent Test**: after a run, the dimension has exactly one "unknown" row and one
"not applicable" row, each with its own fixed surrogate key and a fixed business key, and
each recognizable by its attributes.

**Acceptance Scenarios**:

1. **Given** the dimension, **When** it is read, **Then** it contains one "unknown"
   member and one "not applicable" member, in addition to the silver users.
2. **Given** the two members, **When** they are read on any later update, **Then** their
   surrogate keys and business keys are the same values as before.
3. **Given** a member row, **When** its descriptive attributes are read, **Then** they
   say "unknown" or "not applicable" in Portuguese, so a report shows a readable label.

---

### Edge Cases

- **A sale references a user that silver rejected.** The user gets an inferred row
  (FR-013), so the sale finds a row. If silver later accepts the user, the real values
  replace the placeholders under the same key.
- **A sale with an empty `usuario_uuid`.** No inferred row can be keyed on it. There are none
  on 2026-11-05. Resolving such a sale, for example to `-1`, is the fact's concern (feature
  013).
- **A user reappears in silver with changed attributes.** Silver appends and does not
  merge (feature 006), so today each key occurs once. If a key ever occurred twice, the
  dimension would still hold one row per key (SCD type 1: latest values win) and keep its
  surrogate key.
- **A user disappears from silver.** Silver never deletes users, and it delivers no delete
  event. If a row were removed from silver, the dimension would keep the user's row with
  its last values, because the `AUTO CDC` flow has no delete condition.
- **Invalid email.** 29,599 users have an email without `@` (counted, not dropped, in
  silver). The dimension keeps them as they are; it does not re-apply silver's rules.
- **Same name in two sources.** A site user and an employee with the same name are two
  rows, because their business keys differ.
- **Member keys colliding with user keys.** The members' business keys are fixed values
  that a real `usuario_uuid` (an `md5` hash) can never take.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide the gold dimension `workspace.gold.dim_usuario`, a
  streaming table fed from `workspace.silver.tb_usuario` by an `AUTO CDC` flow.
- **FR-002**: The dimension MUST have exactly these columns:

  | Column | Type | Meaning |
  |---|---|---|
  | `sk_usuario` | BIGINT | surrogate key |
  | `usuario_uuid` | STRING | business key, the silver hash key |
  | `nome_usuario` | STRING | name |
  | `email_usuario` | STRING | email |
  | `idade_usuario` | INT | age |
  | `sexo_usuario` | STRING | sex |
  | `estado_usuario` | STRING | state |
  | `profissao_usuario` | STRING | profession |
  | `empresa_usuario` | STRING | company; empty for site users |
  | `origem` | STRING | record source (`API`, `ARQUIVO`) |
  | `data_carga` | TIMESTAMP | time gold last wrote the row; never silver's `data_carga` |

- **FR-003**: The dimension MUST hold one row per `usuario_uuid` of silver, plus one
  inferred row per user of FR-013, plus the two members of FR-007. Its grain is one user.
- **FR-004**: The dimension MUST be SCD type 1, applied by `AUTO CDC ... STORED AS SCD TYPE
  1`, keyed on `usuario_uuid` and sequenced by silver's `data_carga`: a user's attributes
  are the latest values in silver, and no history is kept.
- **FR-005**: `sk_usuario` MUST be a single column, unique, never empty, and MUST keep
  its value for a given user across every pipeline update, refresh included. A mechanism
  that can reassign keys when the dimension is recomputed MUST NOT be used. Real users'
  keys MUST be non-negative, so that a negative key always means a member of FR-007.
- **FR-006**: The dimension MUST retain `usuario_uuid` as its business key, so that
  facts resolve `sk_usuario` by joining on it.
- **FR-007**: The dimension MUST contain two members with fixed surrogate keys and fixed
  business keys: "unknown" (`Desconhecido`) and "not applicable" (`Não se aplica`). Their
  descriptive text attributes carry that label; their numeric attribute is empty.
- **FR-008**: The dimension MUST NOT declare expectations (owner, 2026-11-04; constitution
  v2.0.0, Principle III). That `sk_usuario` and `usuario_uuid` are never empty MUST be
  verified by query after a load. An empty key does not stop the update.
- **FR-009**: The dimension MUST NOT reference another dimension, and MUST NOT carry the
  silver lineage of other tables.
- **FR-010**: The dimension MUST carry `quality` = `gold`.
- **FR-011**: The definitions MUST follow the constitution: SQL, current syntax, gold
  dataset types, numbered files in a new gold folder of the pipeline.
- **FR-012**: The dimension, its source, grain, keys, members and SCD type MUST be
  described in the project documentation, replacing the earlier pipeline's description
  of `dim_usuario`.

- **FR-013**: The dimension MUST hold an **inferred row** for every `usuario_uuid` that
  `silver.tb_venda` references and `silver.tb_usuario` does not hold (owner, 2026-11-05).
  This is Kimball's inferred member, so that a fact's lookup on `usuario_uuid` always finds a
  row (constitution v3.1.0, Principle V: inner joins need coverage). Rules:
  - its key follows FR-005: `xxhash64(usuario_uuid)` with the sign bit cleared, positive,
    and never changed;
  - its attributes: `Desconhecido` in every text attribute, an empty `idade_usuario`, and
    `origem` = the record source of the sale that references the user (`API` today). An
    inferred row is recognised by a positive key with `nome_usuario = 'Desconhecido'`;
  - users referenced only by `silver.tb_acesso` get no inferred row;
  - if silver later delivers the user, the real row replaces the inferred one in place, with
    the same key.

### Key Entities

- **User dimension row**: one user known to silver, with surrogate key, business key and
  descriptive attributes.
- **Inferred user**: a user that sales reference but silver rejected. It has a real key,
  and its attributes are placeholders until silver delivers the user.
- **Default member**: the "unknown" or "not applicable" user, a fixed row that facts point
  to when a user is missing or does not apply.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Rows in `dim_usuario` = distinct users in `silver.tb_usuario` + inferred
  users + 2, with a difference of 0 (941,234 + 4,362 + 2 = 945,598 on 2026-11-05).
- **SC-002**: 0 rows have an empty `sk_usuario` or `usuario_uuid`; no two rows share
  either.
- **SC-003**: For 100% of silver users, the dimension's attributes equal silver's.
- **SC-004**: After a second update with no new data, 100% of previously recorded
  surrogate keys are unchanged, including the two members', and 100% of rows keep the same
  `data_carga`.
- **SC-005**: Exactly 1 "unknown" row and 1 "not applicable" row exist.
- **SC-006**: 100% of `usuario_uuid` values referenced by silver sales have a row in the
  dimension: an anti join of `silver.tb_venda` against `dim_usuario` on `usuario_uuid` returns
  0 rows. The 4,362 previously absent users are inferred rows.

## Assumptions

- **The load-time column is `data_carga`.** The request names it `dt_carga`. The
  constitution fixes the load timestamp's name as `data_carga` across the project
  (Platform and Technology Constraints, Key and lineage columns), and silver already uses
  it. It holds the time gold last wrote the row (owner, 2026-11-04). Silver's `data_carga`
  is not a column of the dimension; it only sequences the `AUTO CDC` flow (FR-004).
- **"No SCD type 2"** means SCD type 1: one current row per user, overwritten when silver
  changes. Silver users are never updated today, so the type matters only for the future.
- **Source**: `silver.tb_usuario`, as the diagram shows (`S3 → G1`). The dimension does
  not read bronze.
- **Default members** are required by the constitution (Principle VII) even though the
  request does not list them. Their exact key values are a planning decision; they must
  not collide with real keys. They load through a one-time snapshot flow.
- **Stable surrogate keys** are required by the constitution (Principle VII). The earlier
  pipeline used an identity column on a materialized view, which Databricks may
  recompute; `doc/known-issues.md` lists it. Identity columns are not supported on `AUTO
  CDC` targets either, so the key is a deterministic function of the business key.
- The dimension does not re-apply silver's quality rules; silver has already decided
  which users exist.
- `fato_venda`, `obt_acesso`, `dim_curso`, `dim_codigos` and the other dimensions are out
  of scope.
- All data is synthetic.
