CREATE OR REFRESH STREAMING TABLE dataslight_dev.silver.tb_curso;

APPLY CHANGES INTO dataslight_dev.silver.tb_curso
FROM STREAM(vw_bronze_tb_curso)
    KEYS (curso_uuid)
    APPLY AS DELETE WHEN change_type = "delete"
    SEQUENCE BY timestamp_change
    COLUMNS * EXCEPT (timestamp_change, change_type, _rescued_data, processing_time, source_file_name)
    STORED AS SCD TYPE 1;