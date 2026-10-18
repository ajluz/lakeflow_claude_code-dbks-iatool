-- Camada silver: usuários de duas origens, API e ARQUIVO.
-- Cada origem alimenta a tabela pelo seu próprio fluxo de inserção (append flow), sem UNION.
-- API: eventos válidos de temp_tb_validacao_api que trazem usuário; usuario_uuid usa a mesma
--   expressão de tb_acesso.
-- ARQUIVO: vendas corporativas de vw_bronze_dados_files; usuario_uuid = empresa + funcionário.
-- usuario_uuid é único hoje nas duas origens; a unicidade é verificada a cada carga.
-- check_sexo_usuario descarta a linha (exclusão declarada, não vai para a quarentena;
--   constituição v1.7.0, Princípio IV);
-- check_email_usuario apenas mede.

CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_usuario (
  CONSTRAINT check_sexo_usuario  EXPECT (sexo_usuario IS NOT NULL AND sexo_usuario IN ('M', 'F')) ON VIOLATION DROP ROW,
  CONSTRAINT check_email_usuario EXPECT (email_usuario IS NOT NULL AND email_usuario LIKE '%@%'),
  CONSTRAINT check_usuario_uuid  EXPECT (usuario_uuid IS NOT NULL)
)
COMMENT 'Usuários do site (API) e funcionários das empresas parceiras (ARQUIVO).'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_usuario_api_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
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

CREATE FLOW silver_tb_usuario_arquivo_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
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
