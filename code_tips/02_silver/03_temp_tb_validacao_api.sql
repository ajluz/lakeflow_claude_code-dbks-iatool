CREATE OR REFRESH TEMPORARY STREAMING TABLE workspace.silver.temp_tb_validacao_api
  (
  CONSTRAINT curso_invalido EXPECT (
    payload.info_produto.product_name IS NULL
    OR payload.info_produto.product_name != 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    ),
  
  CONSTRAINT valor_invalido EXPECT (
    payload.info_pagamento.valor IS NULL
    OR payload.info_pagamento.valor != '0.00'
    ),
  
  CONSTRAINT forma_pagamento_invalido EXPECT (
    payload.info_pagamento.forma_pagamento IS NULL
    OR payload.info_pagamento.forma_pagamento != '-----'
    )
  ) 
  PARTITIONED BY (fl_registro_invalido)
  AS
    SELECT
      *,
      CASE WHEN 
        payload.info_produto.product_name == 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' 
        OR payload.info_pagamento.forma_pagamento == '-----'
        OR payload.info_pagamento.valor == '0.00'
          THEN TRUE 
        ELSE FALSE 
      END AS fl_registro_invalido
    FROM STREAM(vw_bronze_dados_api);