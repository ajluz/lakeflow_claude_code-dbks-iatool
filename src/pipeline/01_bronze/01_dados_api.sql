-- Camada bronze: eventos de acesso ao site.
-- Origem: API do site, entregue como arquivos JSON na pasta stream/ do volume landing.

CREATE OR REFRESH STREAMING TABLE workspace.bronze.dados_api
COMMENT 'Eventos de acesso ao site recebidos da API, exatamente como chegaram.'
TBLPROPERTIES ("quality" = "bronze")
AS
SELECT
  current_timestamp() AS processing_time,
  _metadata.file_path AS source_file_name,
  *
FROM STREAM read_files(
  '/Volumes/workspace/bronze/landing/stream/',
  format => 'json'
);
