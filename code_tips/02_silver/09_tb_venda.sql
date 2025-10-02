CREATE OR REFRESH STREAMING LIVE TABLE workspace.silver.tb_venda
    TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_venda_api_flow
  AS 
    INSERT INTO workspace.silver.tb_venda BY NAME
    SELECT * 
    FROM STREAM(vw_silver_tb_venda_api);

CREATE FLOW silver_tb_venda_files_flow
  AS 
    INSERT INTO workspace.silver.tb_venda BY NAME
    SELECT * 
    FROM STREAM(vw_silver_tb_venda_files);