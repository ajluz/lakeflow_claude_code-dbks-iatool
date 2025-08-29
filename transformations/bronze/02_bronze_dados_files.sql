CREATE OR REFRESH STREAMING LIVE TABLE dataslight_dev.bronze.dados_files
TBLPROPERTIES ("quality" = "bronze")
AS 
  SELECT 
    current_timestamp() AS processing_time, 
    _metadata.file_path AS source_file_name, 
    *
  FROM cloud_files(
    "/Volumes/dataslight_dev/bronze/landing/files/", 
    "csv", 
    map(
      "cloudFiles.inferColumnTypes", "true",
      "sep",",",
      "header","true"
      )
  )