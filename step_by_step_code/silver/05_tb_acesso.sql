CREATE OR REPLACE STREAMING LIVE TABLE dataslight_dev.silver.tb_acesso (
  CONSTRAINT check_endereco_ip_acesso EXPECT (
          endereco_ip_acesso != '999.999.999.999'
      ) ON VIOLATION DROP ROW,
      CONSTRAINT check_local_acesso EXPECT (
          local_acesso != 'unknown'
      ) 
      -- ON VIOLATION FAIL UPDATE
  )
  TBLPROPERTIES ("quality" = "silver")
  AS 
  SELECT 
      CAST(access_date AS TIMESTAMP) AS timestamp_acesso,
      ip_address AS endereco_ip_acesso,
      CASE 
        WHEN access_point IN ('iphone','android') 
          THEN 'Mobile' 
        WHEN access_point IN ('chrome', 'safari', 'firefox')
          THEN 'Computador'
      ELSE 'unknown' END AS local_acesso,
      md5(concat(
        CAST(access_date AS TIMESTAMP),
             ip_address,
             CASE 
                WHEN access_point IN ('iphone','android') 
                  THEN 'Mobile' 
                WHEN access_point IN ('chrome', 'safari', 'firefox')
                  THEN 'Computador'
            ELSE 'unknown' END
        )) AS acesso_uuid,
        md5(concat(
            CAST(access_date AS TIMESTAMP),
            payload.info_usuario.nome
        )) AS usuario_uuid,
      md5(payload.info_produto.product_name) AS curso_uuid,
      'API' AS origem,
      getdate() AS data_carga
    FROM STREAM(dataslight_dev.silver.temp_tb_validacao_api)
    WHERE fl_registro_invalido=FALSE;