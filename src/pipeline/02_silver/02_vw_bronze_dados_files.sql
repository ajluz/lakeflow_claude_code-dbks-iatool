-- Camada silver: view de fronteira bronze-silver da origem ARQUIVO (vendas corporativas).
-- Entrega as vendas do bronze sem as colunas de linhagem source_file_name e _rescued_data,
-- que pertencem apenas ao bronze. Não filtra, não converte e não aplica regras.

CREATE TEMPORARY VIEW vw_bronze_dados_files
COMMENT 'Vendas corporativas vindas do bronze, sem source_file_name e _rescued_data.'
AS
SELECT
  * EXCEPT (source_file_name, _rescued_data)
FROM STREAM(presentation.bronze.dados_files);
