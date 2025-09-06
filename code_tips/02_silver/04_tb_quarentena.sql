CREATE OR REFRESH STREAMING LIVE TABLE dataslight_dev.silver.tb_quarentena
TBLPROPERTIES ("quality" = "silver")
  AS 
    SELECT * 
    FROM STREAM(dataslight_dev.silver.temp_tb_validacao_api)
    WHERE fl_registro_invalido=TRUE;