-- Camada silver: view do fluxo da origem ARQUIVO para tb_usuario.
-- Lê as vendas corporativas de vw_bronze_dados_files e entrega exatamente as colunas de
-- tb_usuario. usuario_uuid = empresa + funcionário.

CREATE TEMPORARY VIEW vw_silver_tb_usuario_files
COMMENT 'Usuários vindos das vendas corporativas, no formato de tb_usuario.'
AS
SELECT
  md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''))) AS usuario_uuid,
  nome_funcionario                            AS nome_usuario,
  email_funcionario                           AS email_usuario,
  try_cast(idade AS INT)                      AS idade_usuario,
  sexo                                        AS sexo_usuario,
  estado                                      AS estado_usuario,
  profissao                                   AS profissao_usuario,
  nome_empresa                                AS empresa_usuario,
  'ARQUIVO'                                   AS origem,
  current_timestamp()                         AS data_carga
FROM STREAM(vw_bronze_dados_files);
