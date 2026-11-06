-- Camada silver: catálogo de cursos, a versão mais recente de cada curso (SCD tipo 1).
-- Lê as mudanças do catálogo em vw_bronze_tb_curso por um fluxo AUTO CDC:
--   chave: curso_uuid, o identificador entregue pela origem (sem chave hash: exceção de
--     tb_curso no Princípio VI);
--   ordem: timestamp_change, para que uma mudança antiga que chegue tarde não sobrescreva
--     uma mais nova;
--   exclusão: change_type = 'delete' remove o curso; os demais mantêm seus valores mais
--     recentes.
-- As colunas de controle (change_type, timestamp_change, processing_time) conduzem a
-- mudança e saem da tabela por COLUMNS * EXCEPT.
-- As expectativas apenas medem. Atualização e exclusão são demonstradas na palestra.

CREATE OR REFRESH STREAMING TABLE presentation.silver.tb_curso (
  CONSTRAINT check_curso_uuid  EXPECT (curso_uuid IS NOT NULL),
  CONSTRAINT check_nome_curso  EXPECT (nome_curso IS NOT NULL),
  CONSTRAINT check_valor_curso EXPECT (valor_curso IS NOT NULL AND valor_curso > 0)
)
COMMENT 'Catálogo de cursos: um registro por curso, com os valores da mudança mais recente; cursos excluídos não aparecem.'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_curso_flow AS AUTO CDC INTO presentation.silver.tb_curso
FROM STREAM(vw_bronze_tb_curso)
KEYS (curso_uuid)
APPLY AS DELETE WHEN change_type = 'delete'
SEQUENCE BY timestamp_change
COLUMNS * EXCEPT (change_type, timestamp_change, processing_time)
STORED AS SCD TYPE 1;
