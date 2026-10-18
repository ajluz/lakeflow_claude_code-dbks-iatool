-- Camada silver: eventos válidos da origem API.
-- Lê apenas o lado válido de temp_tb_validacao_api (fl_registro_invalido = false).
-- É a definição única de usuario_uuid e curso_uuid da origem API: as tabelas seguintes
-- reutilizam estas chaves em vez de recalculá-las. curso_uuid é igual ao identificador
-- entregue pelo catálogo de cursos (md5 do nome do curso).

CREATE TEMPORARY VIEW vw_silver_eventos_api
COMMENT 'Eventos válidos da API (fl_registro_invalido = false), com timestamp_acesso e as chaves usuario_uuid e curso_uuid, definidas uma única vez.'
AS
SELECT
  *,
  try_to_timestamp(access_date) AS timestamp_acesso,
  CASE WHEN payload.info_usuario.nome IS NOT NULL
       THEN md5(concat_ws('||', coalesce(cast(timestamp_acesso AS STRING), ''), payload.info_usuario.nome))
  END AS usuario_uuid,
  CASE WHEN payload.info_produto.product_name IS NOT NULL
       THEN md5(payload.info_produto.product_name)
  END AS curso_uuid
FROM STREAM(workspace.silver.temp_tb_validacao_api)
WHERE NOT fl_registro_invalido;
