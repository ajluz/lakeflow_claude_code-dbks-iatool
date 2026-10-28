# Contract: The Sales Table and Its Flow Views

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-10-28

Gold (`fato_venda`, `dim_codigos`, `obt_acesso`) will rely on `tb_venda` and its keys.
This document fixes the shape of the three definitions.

## Files

| File | Dataset | Reads |
|---|---|---|
| `src/pipeline/02_silver/09_vw_silver_tb_venda_api.sql` | `vw_silver_tb_venda_api` (flow view) | `STREAM(workspace.silver.temp_tb_validacao_api)`, valid events with a payment |
| `src/pipeline/02_silver/10_vw_silver_tb_venda_files.sql` | `vw_silver_tb_venda_files` (flow view) | `STREAM(vw_bronze_dados_files)` |
| `src/pipeline/02_silver/11_tb_venda.sql` | `workspace.silver.tb_venda` and its two flows | the two flow views |

## Flow views

Each selects exactly the 13 columns of the [data model](../data-model.md), in its order
and with its types. The API view keeps the filter
`WHERE NOT fl_registro_invalido AND payload.info_pagamento IS NOT NULL`, and its inner
query defines `timestamp_acesso`, `endereco_ip_acesso`, `local_acesso`, `acesso_uuid`,
`usuario_uuid` and `curso_uuid` with the same text as `05_tb_acesso.sql`.

## `11_tb_venda.sql`

```sql
CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_venda (
  CONSTRAINT check_venda_uuid   EXPECT (venda_uuid IS NOT NULL),
  CONSTRAINT check_usuario_uuid EXPECT (usuario_uuid IS NOT NULL),
  CONSTRAINT check_curso_uuid   EXPECT (curso_uuid IS NOT NULL),
  CONSTRAINT check_data_venda   EXPECT (data_venda IS NOT NULL),
  CONSTRAINT check_valor_pago   EXPECT (valor_pago IS NOT NULL AND valor_pago > 0)
)
COMMENT '<Portuguese>'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_venda_api_flow AS
INSERT INTO workspace.silver.tb_venda BY NAME
SELECT * FROM STREAM(vw_silver_tb_venda_api);

CREATE FLOW silver_tb_venda_files_flow AS
INSERT INTO workspace.silver.tb_venda BY NAME
SELECT * FROM STREAM(vw_silver_tb_venda_files);
```

## What a definition must not contain

| Forbidden | Why |
|---|---|
| `UNION` across the two sources; `AUTO CDC`; `AS SELECT` on the target | Principle V; the skill (never `AS SELECT` with flows) |
| any query logic in a flow beyond `SELECT * FROM STREAM(<flow view>)` | constitution v1.9.0 (flow views) |
| a read of `workspace.bronze.*`, or of the validation table's flagged rows | Principle I; feature 004's consumer rule |
| an `acesso_uuid`, `usuario_uuid` or `curso_uuid` expression whose text differs from the file that defined it | Principle VI |
| `uuid()`, `rand()` or a load time inside a key; bare `concat` | Principle VI |
| `ON VIOLATION DROP ROW` or `FAIL UPDATE` | spec FR-011: every rule only counts |
| `DOUBLE` arithmetic on amounts or discounts | research Decision 5 |
| `ai_*` functions | constitution v1.10.0 |
| a materialized view, `PARTITIONED BY`, `CLUSTER BY` | Principle V |
| columns beyond the 13 | spec FR-002 |

## What consumers may rely on

- `tb_venda` holds one row per sale, `venda_uuid` unique (verified after each load) and
  never null.
- `percentual_desconto` is one of `0%`, `5%`, `10%`, `15%`; `valor_desconto` is never
  null, `0.00` without a discount.
- `acesso_uuid` is empty exactly on `ARQUIVO` rows. On `API` rows it joins `tb_acesso`,
  except for sales whose event had the address `999.999.999.999`.
- `usuario_uuid` joins `tb_usuario`, except for sales whose user's sex is not `M` or `F`.
- `curso_uuid` is one of the catalog's three identifiers.
- Amounts are `DECIMAL(9,2)` and `valor_pago` = `quantidade_parcelas` × `valor_parcelas`.
