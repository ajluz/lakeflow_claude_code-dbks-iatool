CREATE TEMPORARY STREAMING LIVE VIEW vw_silver_tb_venda_api
AS
  SELECT 
      CAST(access_date AS TIMESTAMP) AS data_venda,
      md5(concat(
          CAST(access_date AS TIMESTAMP),
          ip_address,
          CASE WHEN access_point IN ('iphone','android') THEN 'Mobile' ELSE 'Computador' END
      )) AS acesso_uuid,
      md5(concat(
          CAST(access_date AS TIMESTAMP),
          payload.info_usuario.nome
      )) AS usuario_uuid,
      md5(payload.info_produto.product_name) AS curso_uuid,
      payload.info_pagamento.forma_pagamento,
      CAST(payload.info_pagamento.quantidade_parcelas AS INT) AS quantidade_parcelas,
      CAST(payload.info_pagamento.valor_parcelas AS DECIMAL(9,2)) AS valor_parcelas,
      CAST((payload.info_pagamento.quantidade_parcelas * payload.info_pagamento.valor_parcelas) AS DECIMAL(9,2)) AS valor_pago,
      concat(CAST((payload.info_pagamento.disconto*100) AS INT),"%") AS percentual_disconto,
      CAST((replace(substr(payload.info_produto.valor,4),',','.') * payload.info_pagamento.disconto) AS DECIMAL(9,2)) AS valor_desconto,
      'API' AS origem,
      getdate() AS data_carga
  FROM STREAM(workspace.silver.temp_tb_validacao_api)
  WHERE payload.info_pagamento IS NOT NULL
    AND fl_registro_invalido=FALSE;