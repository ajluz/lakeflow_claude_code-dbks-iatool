# Research: Gold Access One-Big-Table

**Feature**: [spec.md](spec.md) | **Date**: 2026-11-06

Sources:
- constitution v3.1.0 (Principles I, V, VII; Development Workflow);
- `databricks-pipelines` skill: `materialized-view-sql.md`, `sql-basics.md`;
- `doc/pipeline-reference.md` (`tb_acesso`, `tb_venda`, `dim_tempo`, the earlier
  `obt_acesso`) and `doc/architecture.md` (target graph `G5`);
- the earlier pipeline's `code_tips/03_gold/05_obt_acesso.sql` (git history);
- the workspace on 2026-11-06.

No item of the Technical Context was left as NEEDS CLARIFICATION.

## Decision 1: A materialized view

- **Decision**: `workspace.gold.obt_acesso` is a materialized view in
  `src/pipeline/03_gold/08_obt_acesso.sql`, read without `STREAM`.
- **Rationale**:
  - Constitution, Principle V: a gold result that joins tables and aggregates is a
    full-scan result and MUST be a materialized view. Only facts are streaming tables.
  - A view is recomputed from its sources, so the counts always match the current
    accesses and sales (FR-011). Serverless refreshes it incrementally when it can.
  - `dim_codigos` is the precedent: a gold materialized view in the same pipeline.
- **Alternatives considered**: a streaming table over `STREAM(tb_acesso)`. Its counts
  would be frozen when an access is processed, so a sale arriving later would never count;
  and an aggregate in a streaming table is the case Principle V rules out.

## Decision 2: Sales are counted per access before the join

- **Decision**: a CTE `vendas_por_acesso` counts the site sales of `silver.tb_venda` per
  `acesso_uuid` (`WHERE origem = 'API' AND acesso_uuid IS NOT NULL`). The accesses are
  left-joined to it, and `qtde_vendidos` sums its count.
- **Rationale**:
  - FR-008: the link to sales must not remove or duplicate accesses. A plain join to
    `tb_venda` would repeat an access once per sale. On 2026-11-06 each access matched at
    most one sale, but some `acesso_uuid` values occur up to 9 times among the sales whose
    access silver rejected; pre-aggregating keeps the table correct if that ever reaches a
    kept access.
  - File sales carry no `acesso_uuid` (0 on 2026-11-06); the filter states that only site
    sales can link.
  - Sales whose access is not in `tb_acesso` (2,174) are not counted: the table counts
    accesses (spec, US3 scenario 3).
- **Alternatives considered**:
  - The earlier pipeline's `LEFT JOIN tb_venda` with a 0/1 flag: it duplicates accesses
    with more than one sale.
  - `fato_venda`: it stores no access identifier, so it cannot be linked.

## Decision 3: Group by location, address and day

- **Decision**: CTE `acessos` groups `silver.tb_acesso` by `local_acesso`,
  `endereco_ip_acesso` and `CAST(timestamp_acesso AS DATE) AS data`, with:
  - `count(*) AS qtde_acesso`;
  - `count_if(usuario_uuid IS NOT NULL) AS qtde_usuario`;
  - `coalesce(sum(v.qtde_vendas), 0) AS qtde_vendidos`.
- **Rationale**:
  - FR-002 (owner): one row per combination; the counts are summed.
  - The three counts are additive (FR-010).
  - `timestamp_acesso` is never empty on 2026-11-06. If it were, the access would still be
    counted, in a row with an empty `data` (an informative rule of feature 005 records it).
- **Alternatives considered**: one row per access (the earlier pipeline); rejected by the
  owner.

## Decision 4: Calendar attributes through a left join to `dim_tempo`

- **Decision**: the final `SELECT` left-joins `workspace.gold.dim_tempo` on
  `t.data = s.data` and takes the 13 calendar columns from it, with their names and types.
  `data` comes from the access, not from the calendar.
- **Rationale**:
  - FR-005 and FR-009: the calendar attributes come from the conformed calendar, and no
    access is lost if a date were ever missing from it.
  - The calendar covers 2021–2030; accesses run from 2024-06-01 to 2024-06-03, so every row
    gets its attributes (0 without, on 2026-11-06).
  - The members of `dim_tempo` have an empty `data`, so no access matches them.
- **Alternatives considered**: an inner join, which would silently drop an access whose
  date is missing from the calendar.

## Decision 5: Columns, order and types

- **Decision**: exactly the 19 requested columns, in the requested order:

  | Columns | Type | From |
  |---|---|---|
  | `local_acesso`, `endereco_ip_acesso` | STRING | `tb_acesso` |
  | `data` | DATE | the access day |
  | `ano`, `mes_ano`, `dia_mes`, `dia_semana_int`, `dia_ano`, `semana_ano`, `semestre`, `trimestre`, `bimestre` | INT | `dim_tempo` |
  | `mes`, `dia_semana` | STRING | `dim_tempo` |
  | `fl_dia_semana`, `fl_ultimo_dia_mes` | BOOLEAN | `dim_tempo` |
  | `qtde_acesso`, `qtde_usuario`, `qtde_vendidos` | BIGINT | the counts |

- **Rationale**: FR-003, FR-004, FR-005. No surrogate key, no `data_carga` (not requested;
  a `current_timestamp()` column would also block incremental refresh).

## Decision 6: Expected values, measured as a batch on 2026-11-06

The planned query, run as a batch against the current tables:

| Measure | Value |
|---|---|
| Rows (combinations) | 2,516,058 |
| Largest `qtde_acesso` in one row | 2 |
| Sum of `qtde_acesso` | 2,516,192 = rows of `tb_acesso` |
| Sum of `qtde_usuario` | 748,571 = accesses with a user |
| Sum of `qtde_vendidos` | 218,298 = site sales linked to an access |
| Rows without calendar attributes | 0 |

Per location (`qtde_acesso` / `qtde_usuario` / `qtde_vendidos`):
- `Computador` 1,136,377 / 340,520 / 102,148;
- `Mobile` 1,262,684 / 379,439 / 113,846;
- `unknown` 117,131 / 28,612 / 2,304.

Per day:
- 2024-06-01: 881,045 / 262,742 / 77,232;
- 2024-06-02: 880,259 / 260,646 / 75,597;
- 2024-06-03: 754,888 / 225,183 / 65,469.

## Decision 7: Documentation first; no expectations

- **Decision**: rewrite `### obt_acesso` in `doc/pipeline-reference.md` (grain, sources,
  counts) before the first update; no expectations.
- **Rationale**: FR-013 and Principle VII (grain stated before the build); FR-012 and
  Principle III.

## Decision 8: No full refresh, no drop

- **Decision**: the first ordinary update creates the view.
- **Rationale**: no `obt_acesso` exists in `workspace.gold` (checked on 2026-11-06).
