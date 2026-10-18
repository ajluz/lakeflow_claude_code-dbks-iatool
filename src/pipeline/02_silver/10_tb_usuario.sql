-- Camada silver: usuários de duas origens, API e ARQUIVO.
-- Cada origem alimenta a tabela pelo seu próprio fluxo de inserção (append flow), sem UNION.
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
SELECT * FROM STREAM(vw_silver_usuario_api);

CREATE FLOW silver_tb_usuario_arquivo_flow AS
INSERT INTO workspace.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_usuario_arquivo);
