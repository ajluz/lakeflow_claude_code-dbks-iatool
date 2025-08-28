CREATE TEMPORARY STREAMING LIVE VIEW vw_bronze_dados_files
AS 
    SELECT 
      *
      EXCEPT (source_file_name, _rescued_data) 
    FROM STREAM(dataslight_dev.bronze.dados_files)