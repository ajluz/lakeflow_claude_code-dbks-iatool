-- Camada bronze: vendas corporativas.
-- Origem: empresas parceiras, entregue como arquivos CSV na pasta files/ do volume landing.

CREATE OR REFRESH STREAMING TABLE presentation.bronze.dados_files
COMMENT 'Vendas corporativas enviadas por empresas parceiras, exatamente como chegaram.'
TBLPROPERTIES ("quality" = "bronze")
AS
SELECT
  current_timestamp() AS processing_time,
  _metadata.file_path AS source_file_name,
  *
FROM STREAM read_files(
  '/Volumes/workspace/bronze/landing/files/',
  format => 'csv',
  header => true,
  sep => ','
);
