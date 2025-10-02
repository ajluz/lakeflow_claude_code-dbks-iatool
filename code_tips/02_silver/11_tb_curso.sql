CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_curso;

CREATE FLOW silver_tb_curso_flow 
AS 
AUTO CDC INTO workspace.silver.tb_curso
FROM STREAM(vw_bronze_tb_curso)
KEYS (curso_uuid)
APPLY AS DELETE WHEN change_type = "delete"
SEQUENCE BY timestamp_change
COLUMNS * EXCEPT (timestamp_change, change_type, _rescued_data, processing_time, source_file_name)
STORED AS SCD TYPE 1;