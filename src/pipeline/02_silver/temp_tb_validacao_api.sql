-- Camada silver: validação única da origem API, na fronteira bronze-silver.
-- As expectativas apenas medem as violações; nenhuma linha é descartada.
-- fl_registro_invalido = true segue para tb_quarentena; false segue para as tabelas conformadas.

CREATE OR REFRESH PRIVATE STREAMING TABLE workspace.silver.temp_tb_validacao_api (
  CONSTRAINT curso_invalido           EXPECT (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
  CONSTRAINT valor_invalido           EXPECT (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00'),
  CONSTRAINT forma_pagamento_invalido EXPECT (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----'),
  CONSTRAINT registro_nao_conforme    EXPECT (_rescued_data IS NULL)
)
CLUSTER BY (fl_registro_invalido)
COMMENT 'Eventos da API validados: cada evento do bronze, sem alteração, com as regras violadas e a flag fl_registro_invalido.'
TBLPROPERTIES ("quality" = "silver")
AS
SELECT
  *,
  filter(
    array(
      CASE WHEN NOT (payload.info_produto.product_name IS NULL OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx') THEN 'curso_invalido' END,
      CASE WHEN NOT (payload.info_pagamento.valor IS NULL OR payload.info_pagamento.valor != '0.00') THEN 'valor_invalido' END,
      CASE WHEN NOT (payload.info_pagamento.forma_pagamento IS NULL OR payload.info_pagamento.forma_pagamento != '-----') THEN 'forma_pagamento_invalido' END,
      CASE WHEN NOT (_rescued_data IS NULL) THEN 'registro_nao_conforme' END
    ),
    r -> r IS NOT NULL
  ) AS regras_violadas,
  size(regras_violadas) > 0 AS fl_registro_invalido,
  'API' AS origem,
  current_timestamp() AS data_carga
FROM STREAM(workspace.bronze.dados_api);
