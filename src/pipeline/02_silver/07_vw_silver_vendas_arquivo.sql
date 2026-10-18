-- Camada silver: vendas corporativas da origem ARQUIVO.
-- É a definição única de usuario_uuid da origem ARQUIVO (empresa + funcionário): as tabelas
-- seguintes, como as de vendas, reutilizam esta chave em vez de recalculá-la.

CREATE TEMPORARY VIEW vw_silver_vendas_arquivo
COMMENT 'Vendas corporativas com usuario_uuid da origem ARQUIVO, definida uma única vez.'
AS
SELECT
  *,
  md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''))) AS usuario_uuid
FROM STREAM(vw_bronze_dados_files);
