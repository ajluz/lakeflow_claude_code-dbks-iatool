CREATE OR REFRESH STREAMING LIVE TABLE workspace.bronze.dados_api
TBLPROPERTIES ("quality" = "bronze")
AS 
  SELECT 
    current_timestamp() AS processing_time, 
    _metadata.file_path AS source_file_name, 
    *
  FROM cloud_files(
    "/Volumes/workspace/bronze/landing/stream/", 
    "json", 
    map("cloudFiles.inferColumnTypes", "true")
  )