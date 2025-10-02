CREATE TEMPORARY STREAMING LIVE VIEW vw_bronze_tb_curso
AS 
    SELECT 
        *,
        'DATABASE' AS origem 
    FROM STREAM(workspace.bronze.dados_database);