CREATE TEMPORARY STREAMING LIVE VIEW vw_silver_tb_venda_files
AS
  SELECT
  CAST(data_venda AS TIMESTAMP) AS data_venda,
  CAST(NULL AS STRING) AS acesso_uuid,
  md5(concat(
              nome_empresa,
              nome_funcionario
          )) AS usuario_uuid,
  md5(curso) AS curso_uuid,
  'pix' AS forma_pagamento,
  1 AS quantidade_parcelas,
  CAST((replace(substr(valor,4),',','.') - CAST((replace(substr(valor,4),',','') * (replace(disconto,'%','')/100)) AS DECIMAL(9,2))) AS DECIMAL(9,2)) AS valor_parcelas,
  CAST((replace(substr(valor,4),',','.') - CAST((replace(substr(valor,4),',','') * (replace(disconto,'%','')/100)) AS DECIMAL(9,2))) AS DECIMAL(9,2)) AS valor_pago,
  disconto AS percentual_disconto,
  CAST((replace(substr(valor,4),',','.') * (replace(disconto,'%','')/100)) AS DECIMAL(9,2)) AS valor_desconto,
  'ARQUIVO' AS origem,
  getdate() AS data_carga
  FROM STREAM(vw_bronze_dados_files)