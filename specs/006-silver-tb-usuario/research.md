# Research: Silver User Table from API Events and Partner Files

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-18

## Revision 2026-10-18: constitution v1.8.0

The owner asked why so many views were being created, and whether
`doc/lakeflow_architecture.png` had been considered. It had not. The owner chose to
match the diagram:
- **Graph**: `tb_usuario` reads `workspace.silver.temp_tb_validacao_api` (valid events
  with a user) and `vw_bronze_dados_files` directly, as the diagram's edges show.
  `vw_silver_eventos_api`, `vw_silver_vendas_arquivo`, `vw_silver_usuario_api` and
  `vw_silver_usuario_arquivo` were removed. Each append flow shapes its columns inline.
- **Keys**: the API `usuario_uuid` is computed in the flow, with the same expression as
  `tb_acesso`. The files `usuario_uuid` is computed in its flow. Constitution v1.8.0
  replaced "one definition per key" with "one expression per key".
- **Files**: `02_vw_bronze_dados_files.sql` (was `06_`) and `06_tb_usuario.sql` (was
  `10_`), in the diagram's reading order.
- **Data**: the key values do not change, so the rows after the refresh are the same.
  `tb_usuario` needs a refresh, which needs the owner's approval.

The sections below record earlier designs (`AUTO CDC`, then shaping views) and remain as
history.

Sources consulted: constitution v1.7.0; the `databricks-pipelines` skill
(`references/auto-cdc-sql.md`, `streaming-table-sql.md`, `expectations-sql.md`,
`temporary-view-sql.md`); the Databricks reference page for `AUTO CDC INTO` in pipelines;
features 004 and 005 (contracts and data models); the generator in
`explorations/functions.py`; the earlier pipeline's description of `tb_usuario` in
`doc/pipeline-reference.md`; queries on the workspace (profile `databricks-free`) on
2026-10-18.

## Facts established

| Fact | API (valid events with a user) | Files (`workspace.bronze.dados_files`) |
|---|---|---|
| Rows | 756,249 | 200,000 (2 files, 58 sale dates) |
| Distinct user keys | 756,249: unique (time + name) | 200,000: unique (company + name), at most 1 row per key |
| Sex values | `F` 370,743; `M` 370,491; `X` 15,015; no nulls | `M` 100,550; `F` 99,450; no other value |
| Email without `@` (or empty) | 30,190 | 0 |
| Age | STRING in the payload; every value casts to INT | INT already; no nulls |
| Empty company or employee name | n/a | 0 / 0 |
| Keys whose attributes vary between rows | n/a | 0 |
| Keys with valid and invalid sex in different rows | n/a | 0 |
| Expected rows in `tb_usuario` | 756,249 − 15,015 = **741,234** | **200,000** |

The files source grew from 100,000 to 200,000 rows after feature 003, when the generator
delivered a second file. The new rows are new employees, not repeats.

## Decision 1: One append flow per source into one streaming table

- **Decision** (revised 2026-10-18 by the owner): `workspace.silver.tb_usuario` is
  declared as an empty streaming table carrying the expectations. Two flows write into
  it, both `INSERT INTO ... BY NAME`:
  - `silver_tb_usuario_api_flow` from `STREAM(vw_silver_usuario_api)`;
  - `silver_tb_usuario_arquivo_flow` from `STREAM(vw_silver_usuario_arquivo)`.
- **Rationale**: Principle V requires one append flow per source and no `UNION`. Both
  user keys are unique in today's data: 756,249 API keys for 756,249 rows, and 200,000
  files keys for 200,000 rows. Appending therefore already gives a unique `usuario_uuid`.
  Principle VI requires deduplication only for a table that "legitimately receives the
  same business key more than once", and this one does not. Uniqueness is verified after
  every load (quickstart).
- **Revision history**: the first design used two `AUTO CDC` SCD type 1 flows keyed on
  `usuario_uuid`, to merge a re-delivered employee. It was deployed in update
  `e89d459d-...`. The owner questioned it: no history is needed, and the data has no
  repeats. They chose append flows as simpler, at the cost of verifying uniqueness rather
  than enforcing it. The switch needed a refresh of `tb_usuario` alone, which the owner
  approved. It also removes the earlier Complexity Tracking deviation (an `AUTO CDC`
  without a delete condition).
- **Risk**: a later file that re-delivers an employee would add a second row with the
  same key. The uniqueness check catches it, and deduplication (`AUTO CDC` keyed on the
  hash key, Principle VI) would then be planned as a change.
- **Alternatives considered**: `UNION ALL` in one query, as the earlier pipeline did:
  forbidden by Principle V. `AUTO CDC` SCD type 1: the first design, replaced as above.

## Decision 2: No sequencing column

- **Decision**: the shaping views carry exactly the 10 target columns. The `sequencia`
  struct of the first design was removed with `AUTO CDC`.
- **Rationale**: append flows keep every row. Nothing chooses between deliveries, so
  nothing needs ordering.

## Decision 3: Views and key definitions

| File | View | Purpose |
|---|---|---|
| `06_vw_bronze_dados_files.sql` | `vw_bronze_dados_files` | boundary view (Principle I): `STREAM(workspace.bronze.dados_files)` minus `source_file_name`, `_rescued_data`. Nothing else |
| `07_vw_silver_vendas_arquivo.sql` | `vw_silver_vendas_arquivo` | shared view of the files source: every column plus `usuario_uuid`, the files user key, defined once (Principle VI). Later sales tables reuse it |
| `08_vw_silver_usuario_api.sql` | `vw_silver_usuario_api` | API users in the target's shape, from `STREAM(vw_silver_eventos_api)` with `WHERE usuario_uuid IS NOT NULL` |
| `09_vw_silver_usuario_arquivo.sql` | `vw_silver_usuario_arquivo` | files users in the target's shape, from `STREAM(vw_silver_vendas_arquivo)` |

- **Files key**: `md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, '')))`.
  Each component is a STRING, a null becomes `''`, and the delimiter is `'||'`
  (Principle VI). The company comes first, as in the request.
- **API key**: reused from `vw_silver_eventos_api` (feature 005), never recomputed.
- **Shaping views exist** to keep each flow a plain `SELECT *`, with the renames and casts
  in one readable place per source. They also keep the two flows' schemas visibly
  identical.
- **Naming**: the files source is `ARQUIVO` in the constitution, so the views use
  `arquivo`. Flows follow `<layer>_<target>[_<source>]_flow`.
- **Record source in the key**: not added. The two keys are built from different fields,
  so the sources cannot issue the same identifier for different people (Principle VI asks
  for it only when they can). Uniqueness across the whole table is verified.

## Decision 4: Columns and casts

| Column | API view | Files view |
|---|---|---|
| `usuario_uuid` | `usuario_uuid` | `usuario_uuid` |
| `nome_usuario` | `payload.info_usuario.nome` | `nome_funcionario` |
| `email_usuario` | `payload.info_usuario.email` | `email_funcionario` |
| `idade_usuario` | `try_cast(payload.info_usuario.idade AS INT)` | `try_cast(idade AS INT)` |
| `sexo_usuario` | `payload.info_usuario.sexo` | `sexo` |
| `estado_usuario` | `payload.info_usuario.estado` | `estado` |
| `profissao_usuario` | `payload.info_usuario.profissao` | `profissao` |
| `empresa_usuario` | `CAST(NULL AS STRING)` | `nome_empresa` |
| `origem` | `'API'` | `'ARQUIVO'` |
| `data_carga` | `current_timestamp()` | `current_timestamp()` |

`try_cast` turns a non-integer age into null without failing the update (spec edge case).
`empresa_usuario` is typed in the API view so that both flows have the same schema.

## Decision 5: The three expectations

| Name | Condition | Action | Why |
|---|---|---|---|
| `check_sexo_usuario` | `sexo_usuario IS NOT NULL AND sexo_usuario IN ('M', 'F')` | `ON VIOLATION DROP ROW` | the request. Declared exclusion under Principle IV (v1.7.0), as for `tb_acesso`: `X` is a generator artifact, and the owner chose not to quarantine conformed-table drops |
| `check_email_usuario` | `email_usuario IS NOT NULL AND email_usuario LIKE '%@%'` | warn | the request: informative only |
| `check_usuario_uuid` | `usuario_uuid IS NOT NULL` | warn | Principle VI: not-null expectation on the hash key |

- Null handling is explicit, so no condition returns null (Principle III).
- Expectations are evaluated on every incoming row, including rows dropped by another
  rule (feature 005's finding). So `check_email_usuario` counts invalid emails among all
  candidate users, including those then dropped for sex.
- The expectations sit on the target streaming table and apply to the rows of both
  append flows.
- Declaring `CONSTRAINT` clauses on a target with no column list or query was accepted
  by the dry run and the update of 2026-10-18.

## Decision 6: Rollout

- New datasets only. Upload, dry run, one update. No refresh of existing tables.
- `vw_silver_eventos_api` (feature 005) gains a new reader. Its definition does not
  change.
- Free Edition quota:
  - stop the warehouse and wait about 4 minutes between updates;
  - never stop the warehouse while queries are still running on it (a job doing that on
    2026-10-18 cancelled other queries);
  - a serverless notebook left attached holds the quota too.
- If the first real update fails after creating `tb_usuario`, and a fix changes its
  columns, ask the owner to refresh `tb_usuario` alone (feature 004's lesson).
