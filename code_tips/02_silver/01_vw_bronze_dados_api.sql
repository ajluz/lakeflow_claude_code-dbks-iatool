CREATE TEMPORARY STREAMING LIVE VIEW vw_bronze_dados_api
AS 
    SELECT 
      *
      EXCEPT (source_file_name, _rescued_data) 
    FROM STREAM(workspace.bronze.dados_api)