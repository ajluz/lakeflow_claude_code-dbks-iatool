-- Camada silver: usuários de duas origens, API e ARQUIVO.
-- Cada origem alimenta a tabela pelo seu próprio fluxo de inserção (append flow), sem UNION.
-- A lógica de cada fluxo fica na sua view: vw_silver_tb_usuario_api e
-- vw_silver_tb_usuario_files.
-- usuario_uuid é único hoje nas duas origens; a unicidade é verificada a cada carga.
-- check_sexo_usuario é apenas informativa (dono, 2026-11-06): o ON VIOLATION DROP ROW fica
--   comentado para mostrar a mudança. As views gravam o sexo como NULL quando não é M ou F,
--   e a regra conta essas linhas como falhas, sem descartá-las;
-- check_email_usuario apenas mede.

CREATE OR REFRESH STREAMING TABLE presentation.silver.tb_usuario (
  CONSTRAINT check_sexo_usuario  EXPECT (sexo_usuario IS NOT NULL AND sexo_usuario IN ('M', 'F')), -- ON VIOLATION DROP ROW
  CONSTRAINT check_email_usuario EXPECT (email_usuario IS NOT NULL AND email_usuario LIKE '%@%'),
  CONSTRAINT check_usuario_uuid  EXPECT (usuario_uuid IS NOT NULL)
)
COMMENT 'Usuários do site (API) e funcionários das empresas parceiras (ARQUIVO).'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_usuario_api_flow AS
INSERT INTO presentation.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_tb_usuario_api);

CREATE FLOW silver_tb_usuario_files_flow AS
INSERT INTO presentation.silver.tb_usuario BY NAME
SELECT * FROM STREAM(vw_silver_tb_usuario_files);
