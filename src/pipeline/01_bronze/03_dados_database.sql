-- Camada bronze: mudanças do catálogo de cursos.
-- Origem: banco de dados do catálogo, entregue como change feed em arquivos CSV na pasta
-- database/ do volume landing.

CREATE OR REFRESH STREAMING TABLE presentation.bronze.dados_database
COMMENT 'Mudanças do catálogo de cursos (insert, update, delete), exatamente como chegaram.'
TBLPROPERTIES ("quality" = "bronze")
AS
SELECT
  current_timestamp() AS processing_time,
  _metadata.file_path AS source_file_name,
  *
FROM STREAM read_files(
  '/Volumes/workspace/bronze/landing/database/',
  format => 'csv',
  header => true,
  sep => ','
);
