# Contract: The Gold User Dimension

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-28

`fato_venda` and `obt_acesso` will rely on `dim_usuario`'s keys and members.

## File

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/03_gold/01_dim_usuario.sql` | `workspace.gold.dim_usuario` (materialized view) | `workspace.silver.tb_usuario`, batch |

## `01_dim_usuario.sql`

```sql
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_usuario (
  CONSTRAINT check_sk_usuario   EXPECT (sk_usuario IS NOT NULL)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT check_usuario_uuid EXPECT (usuario_uuid IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT '<Portuguese>'
TBLPROPERTIES ("quality" = "gold")
AS
SELECT xxhash64(usuario_uuid) AS sk_usuario, usuario_uuid, nome_usuario, email_usuario,
       idade_usuario, sexo_usuario, estado_usuario, profissao_usuario, empresa_usuario,
       origem, current_timestamp() AS data_carga
FROM workspace.silver.tb_usuario
QUALIFY row_number() OVER (PARTITION BY usuario_uuid ORDER BY data_carga DESC) = 1
UNION ALL
SELECT CAST(-1 AS BIGINT), '-1', 'Desconhecido', 'Desconhecido', CAST(NULL AS INT),
       'Desconhecido', 'Desconhecido', 'Desconhecido', 'Desconhecido', 'Desconhecido',
       current_timestamp()
UNION ALL
SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica', CAST(NULL AS INT),
       'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica',
       current_timestamp();
```

The shape above is binding; the exact layout and comments are the implementer's. If
`QUALIFY` inside a `UNION ALL` branch is rejected, wrap the silver branch in a subquery.

## What the definition must not contain

| Forbidden | Why |
|---|---|
| `GENERATED ... AS IDENTITY`, `row_number()` or `monotonically_increasing_id()` as the surrogate key | Principle VII (keys that can be reassigned); identity is not supported on materialized views |
| `STREAM(...)`, `CREATE OR REFRESH STREAMING TABLE` | Principle V: gold full-scan result |
| a read of `workspace.bronze.*` or of another dimension | Principles I and VII |
| `ON VIOLATION DROP ROW`; silver's quality rules | spec: the dimension does not re-apply silver's rules |
| `dt_carga` | the constitution's name is `data_carga` |
| `PARTITIONED BY`, `CLUSTER BY`, `ai_*` | Principle V; v1.10.0 |
| columns beyond the 11 | spec FR-002 |

## What consumers may rely on

- One row per `usuario_uuid`; `sk_usuario` and `usuario_uuid` unique and never null.
- `sk_usuario` never changes for a given user, whatever is refreshed.
- `sk_usuario = -1` is "unknown", `-2` is "not applicable"; both always exist.
- Attributes equal silver's latest row for the user.
