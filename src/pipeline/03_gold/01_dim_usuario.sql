-- Camada gold: dimensão de usuários (dim_usuario).
-- Grão: um usuário. SCD tipo 1: cada usuário tem uma linha com os valores mais recentes de
-- silver.tb_usuario; nenhum histórico é guardado.
-- sk_usuario = xxhash64(usuario_uuid): a chave substituta é calculada a partir da chave de
-- negócio, então nunca muda para o mesmo usuário, em qualquer atualização ou refresh.
-- Colunas de identidade não são suportadas em views materializadas e podem ser
-- reatribuídas.
-- Membros padrão: -1 'Desconhecido' e -2 'Não se aplica', com chaves fixas.
-- Os fatos resolvem sk_usuario pela junção em usuario_uuid e usam -1 quando não há
-- correspondência; -2 quando o fato não tem usuário por natureza.
-- data_carga é o horário da atualização que reconstruiu a linha, não o de silver.

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_usuario (
  CONSTRAINT check_sk_usuario   EXPECT (sk_usuario IS NOT NULL)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT check_usuario_uuid EXPECT (usuario_uuid IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Dimensão de usuários: um registro por usuário de silver.tb_usuario (SCD tipo 1), com chave substituta estável e os membros Desconhecido (-1) e Não se aplica (-2).'
TBLPROPERTIES ("quality" = "gold")
AS
SELECT
  xxhash64(u.usuario_uuid) AS sk_usuario,
  u.usuario_uuid,
  u.nome_usuario,
  u.email_usuario,
  u.idade_usuario,
  u.sexo_usuario,
  u.estado_usuario,
  u.profissao_usuario,
  u.empresa_usuario,
  u.origem,
  current_timestamp()      AS data_carga
FROM workspace.silver.tb_usuario AS u
QUALIFY row_number() OVER (PARTITION BY u.usuario_uuid ORDER BY u.data_carga DESC) = 1

UNION ALL

SELECT
  CAST(-1 AS BIGINT)  AS sk_usuario,
  '-1'                AS usuario_uuid,
  'Desconhecido'      AS nome_usuario,
  'Desconhecido'      AS email_usuario,
  CAST(NULL AS INT)   AS idade_usuario,
  'Desconhecido'      AS sexo_usuario,
  'Desconhecido'      AS estado_usuario,
  'Desconhecido'      AS profissao_usuario,
  'Desconhecido'      AS empresa_usuario,
  'Desconhecido'      AS origem,
  current_timestamp() AS data_carga

UNION ALL

SELECT
  CAST(-2 AS BIGINT)  AS sk_usuario,
  '-2'                AS usuario_uuid,
  'Não se aplica'     AS nome_usuario,
  'Não se aplica'     AS email_usuario,
  CAST(NULL AS INT)   AS idade_usuario,
  'Não se aplica'     AS sexo_usuario,
  'Não se aplica'     AS estado_usuario,
  'Não se aplica'     AS profissao_usuario,
  'Não se aplica'     AS empresa_usuario,
  'Não se aplica'     AS origem,
  current_timestamp() AS data_carga;
