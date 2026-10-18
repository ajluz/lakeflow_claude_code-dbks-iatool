-- Camada silver: view do fluxo da origem API para tb_usuario.
-- Lê os eventos válidos de temp_tb_validacao_api que trazem usuário e entrega exatamente as
-- colunas de tb_usuario. usuario_uuid usa a mesma expressão de tb_acesso.

CREATE TEMPORARY VIEW vw_silver_tb_usuario_api
COMMENT 'Usuários vindos dos eventos válidos da API, no formato de tb_usuario.'
AS
SELECT
  md5(concat_ws('||', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome)) AS usuario_uuid,
  payload.info_usuario.nome                   AS nome_usuario,
  payload.info_usuario.email                  AS email_usuario,
  try_cast(payload.info_usuario.idade AS INT) AS idade_usuario,
  payload.info_usuario.sexo                   AS sexo_usuario,
  payload.info_usuario.estado                 AS estado_usuario,
  payload.info_usuario.profissao              AS profissao_usuario,
  CAST(NULL AS STRING)                        AS empresa_usuario,
  'API'                                       AS origem,
  current_timestamp()                         AS data_carga
FROM STREAM(workspace.silver.temp_tb_validacao_api)
WHERE NOT fl_registro_invalido
  AND payload.info_usuario.nome IS NOT NULL;
