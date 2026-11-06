-- Camada silver: acessos ao site vindos da API, um registro por acesso válido.
-- Lê apenas o lado válido de temp_tb_validacao_api (fl_registro_invalido = false).
-- As expectativas mostram as três ações possíveis:
--   check_endereco_ip_acesso descarta a linha (exclusão declarada, não vai para a quarentena;
--     constituição v1.7.0, Princípio IV);
--   check_local_acesso apenas mede;
--   a variante FAIL UPDATE, comentada logo abaixo, interromperia a atualização.
-- Para ativá-la, comente a linha ativa de check_local_acesso e descomente a outra.
-- usuario_uuid usa a mesma expressão de tb_usuario; curso_uuid é igual ao identificador do
-- catálogo de cursos (md5 do nome do curso).

CREATE OR REFRESH STREAMING TABLE presentation.silver.tb_acesso (
  CONSTRAINT check_endereco_ip_acesso EXPECT (endereco_ip_acesso IS NULL OR endereco_ip_acesso != '999.999.999.999') ON VIOLATION DROP ROW,
  CONSTRAINT check_local_acesso       EXPECT (local_acesso != 'unknown'),
  -- CONSTRAINT check_local_acesso    EXPECT (local_acesso != 'unknown') ON VIOLATION FAIL UPDATE,
  CONSTRAINT check_timestamp_acesso   EXPECT (timestamp_acesso IS NOT NULL),
  CONSTRAINT check_acesso_uuid        EXPECT (acesso_uuid IS NOT NULL)
)
COMMENT 'Acessos ao site vindos da API: um registro por acesso válido, com local de acesso e chaves de acesso, usuário e curso.'
TBLPROPERTIES ("quality" = "silver")
AS
SELECT
  try_to_timestamp(access_date) AS timestamp_acesso,
  ip_address AS endereco_ip_acesso,
  CASE WHEN lower(access_point) IN ('iphone', 'android') THEN 'Mobile'
       WHEN lower(access_point) IN ('chrome', 'safari', 'firefox') THEN 'Computador'
       ELSE 'unknown'
  END AS local_acesso,
  md5(concat_ws('||',
      coalesce(cast(timestamp_acesso AS STRING), ''),
      coalesce(endereco_ip_acesso, ''),
      coalesce(local_acesso, ''))) AS acesso_uuid,
  CASE WHEN payload.info_usuario.nome IS NOT NULL
       THEN md5(concat_ws('||', coalesce(cast(try_to_timestamp(access_date) AS STRING), ''), payload.info_usuario.nome))
  END AS usuario_uuid,
  CASE WHEN payload.info_produto.product_name IS NOT NULL
       THEN md5(payload.info_produto.product_name)
  END AS curso_uuid,
  'API' AS origem,
  current_timestamp() AS data_carga
FROM STREAM(presentation.silver.temp_tb_validacao_api)
WHERE NOT fl_registro_invalido;
