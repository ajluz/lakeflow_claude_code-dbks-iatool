-- Camada silver: view de fronteira bronze-silver do catálogo de cursos (origem DATABASE).
-- Entrega as mudanças do catálogo sem as colunas de linhagem source_file_name e
-- _rescued_data, que pertencem apenas ao bronze.
-- Além disso, converte valor_curso para DECIMAL(9,2) e acrescenta origem e data_carga: os
-- fluxos AUTO CDC de tb_curso e, mais tarde, de dim_curso só leem uma view pelo nome e não
-- calculam colunas (constituição v1.11.0, Princípio I).
-- Não filtra, não renomeia e não altera nenhuma outra coluna.

CREATE TEMPORARY VIEW vw_bronze_tb_curso
COMMENT 'Mudanças do catálogo de cursos vindas do bronze, sem source_file_name e _rescued_data, com preço em DECIMAL, origem e data_carga.'
AS
SELECT
  * EXCEPT (source_file_name, _rescued_data, valor_curso),
  CAST(valor_curso AS DECIMAL(9,2)) AS valor_curso,
  'DATABASE'                         AS origem,
  current_timestamp()                AS data_carga
FROM STREAM(presentation.bronze.dados_database);
