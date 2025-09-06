CREATE TEMPORARY STREAMING LIVE VIEW vw_bronze_tb_curso
AS 
    SELECT 
        *,
        'DATABASE' AS origem 
    FROM STREAM(dataslight_dev.bronze.dados_database);