-- Camada silver: usuários da origem ARQUIVO (funcionários das empresas parceiras) no formato
-- de tb_usuario. Reutiliza o usuario_uuid de vw_silver_vendas_arquivo.

CREATE TEMPORARY VIEW vw_silver_usuario_arquivo
COMMENT 'Usuários vindos das vendas corporativas, no formato de tb_usuario.'
AS
SELECT
  usuario_uuid,
  nome_funcionario                            AS nome_usuario,
  email_funcionario                           AS email_usuario,
  try_cast(idade AS INT)                      AS idade_usuario,
  sexo                                        AS sexo_usuario,
  estado                                      AS estado_usuario,
  profissao                                   AS profissao_usuario,
  nome_empresa                                AS empresa_usuario,
  'ARQUIVO'                                   AS origem,
  current_timestamp()                         AS data_carga
FROM STREAM(vw_silver_vendas_arquivo);
