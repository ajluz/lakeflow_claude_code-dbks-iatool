CREATE OR REFRESH STREAMING LIVE TABLE workspace.bronze.dados_database
TBLPROPERTIES ("quality" = "bronze")
AS 
  SELECT 
    current_timestamp() AS processing_time, 
    _metadata.file_path AS source_file_name, 
    *
  FROM cloud_files(
    "/Volumes/workspace/bronze/landing/database/", 
    "csv", 
    map(
      "cloudFiles.inferColumnTypes", "true",
      "sep",",",
      "header","true"
      )
  )