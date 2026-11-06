-- Camada silver: quarentena dos eventos da API.
-- Recebe as linhas de temp_tb_validacao_api com fl_registro_invalido = true, com todas as
-- colunas da validação (evento, regras_violadas, flag, origem, data_carga), para facilitar a
-- identificação do problema, e acrescenta data_carga_quarentena.

CREATE OR REFRESH STREAMING TABLE presentation.silver.tb_quarentena (
  CONSTRAINT regra_violada_registrada EXPECT (size(regras_violadas) > 0)
)
COMMENT 'Quarentena dos eventos da API rejeitados pela validação, sem alteração, com as regras violadas.'
TBLPROPERTIES ("quality" = "silver")
AS
SELECT
  *,
  current_timestamp() AS data_carga_quarentena
FROM STREAM(presentation.silver.temp_tb_validacao_api)
WHERE fl_registro_invalido;
