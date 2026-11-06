-- Camada gold: membros padrão de dim_curso.
-- Desconhecido (-1) e Não se aplica (-2), para fatos cujo curso falta ou não se aplica.
-- O timestamp_change é 1900-01-01: os membros valem para qualquer data de fato, e nenhum
-- evento de curso os fecha.
-- Um fluxo AUTO CDC só lê fontes em stream, então a view lê o stream do catálogo
-- (vw_bronze_tb_curso). O stream do catálogo só dispara a emissão; as linhas de curso não
-- são usadas.
-- Lida uma única vez por gold_dim_curso_membros_flow (AUTO CDC ONCE), que depois fica ocioso.
-- Mesmas colunas, na mesma ordem, de vw_gold_dim_curso_dados_database.

CREATE TEMPORARY VIEW vw_gold_dim_curso_membros
COMMENT 'Membros padrão de dim_curso, Desconhecido (-1) e Não se aplica (-2), no formato do fluxo AUTO CDC.'
AS
SELECT m.*
FROM STREAM(vw_bronze_tb_curso) AS c
CROSS JOIN (
  SELECT CAST(-1 AS BIGINT) AS sk_curso, '-1' AS curso_uuid,
         'Desconhecido' AS nome_curso, 'Desconhecido' AS nivel_curso,
         CAST(NULL AS DECIMAL(9,2)) AS valor_curso, current_timestamp() AS data_carga,
         'insert' AS change_type, TIMESTAMP'1900-01-01' AS timestamp_change
  UNION ALL
  SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica',
         CAST(NULL AS DECIMAL(9,2)), current_timestamp(), 'insert', TIMESTAMP'1900-01-01'
) AS m;
