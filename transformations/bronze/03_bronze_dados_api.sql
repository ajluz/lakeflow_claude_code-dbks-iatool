CREATE OR REFRESH STREAMING LIVE TABLE dataslight_dev.bronze.dados_api
TBLPROPERTIES ("quality" = "bronze")
AS 
  SELECT 
    current_timestamp() AS processing_time, 
    _metadata.file_path AS source_file_name, 
    *
  FROM cloud_files(
    "/Volumes/dataslight_dev/bronze/landing/stream/", 
    "json", 
    map("cloudFiles.inferColumnTypes", "true")
  )