-- Camada silver: usuários da origem API no formato de tb_usuario.
-- Lê os eventos válidos que trazem usuário e reutiliza o usuario_uuid de vw_silver_eventos_api.

CREATE TEMPORARY VIEW vw_silver_usuario_api
COMMENT 'Usuários vindos dos eventos válidos da API, no formato de tb_usuario.'
AS
SELECT
  usuario_uuid,
  payload.info_usuario.nome                   AS nome_usuario,
  payload.info_usuario.email                  AS email_usuario,
  try_cast(payload.info_usuario.idade AS INT) AS idade_usuario,
  payload.info_usuario.sexo                   AS sexo_usuario,
  payload.info_usuario.estado                 AS estado_usuario,
  payload.info_usuario.profissao              AS profissao_usuario,
  CAST(NULL AS STRING)                        AS empresa_usuario,
  'API'                                       AS origem,
  current_timestamp()                         AS data_carga
FROM STREAM(vw_silver_eventos_api)
WHERE usuario_uuid IS NOT NULL;
