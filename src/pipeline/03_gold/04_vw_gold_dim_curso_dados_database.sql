-- Camada gold: view do fluxo AUTO CDC de dim_curso.
-- Lê as mudanças do catálogo por vw_bronze_tb_curso, não por silver.tb_curso: o SCD tipo 2
-- precisa dos eventos de mudança, e tb_curso guarda só a versão mais recente (constituição,
-- Princípio I, exceção de dim_curso).
-- sk_curso: xxhash64 de curso_uuid e timestamp_change com o bit de sinal zerado. Uma chave
-- por versão, que nunca muda e nunca é negativa; chaves negativas ficam para os membros.
-- origem e processing_time ficam de fora (decisão do dono).
-- change_type e timestamp_change só conduzem o fluxo, que os exclui da dimensão.
-- Nenhum filtro e nenhuma regra sobre o feed.

CREATE TEMPORARY VIEW vw_gold_dim_curso_dados_database
COMMENT 'Mudanças do catálogo de cursos com a chave substituta de cada versão, no formato do fluxo AUTO CDC de dim_curso.'
AS
SELECT
  xxhash64(curso_uuid, timestamp_change) & 9223372036854775807 AS sk_curso,
  curso_uuid,
  nome_curso,
  nivel_curso,
  valor_curso,
  data_carga,
  change_type,
  timestamp_change
FROM STREAM(vw_bronze_tb_curso);
