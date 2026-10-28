-- Camada silver: vendas de duas origens, API e ARQUIVO.
-- Cada origem alimenta a tabela pelo seu próprio fluxo de inserção (append flow), sem UNION.
-- A lógica de cada fluxo fica na sua view: vw_silver_tb_venda_api e
-- vw_silver_tb_venda_files.
-- Nenhuma regra descarta linhas: as cinco expectativas apenas medem.
-- acesso_uuid é vazio nas vendas corporativas (ARQUIVO), que não passam pelo site.
-- As chaves de acesso, usuário e curso usam as mesmas expressões de tb_acesso e tb_usuario.
-- venda_uuid é único hoje nas duas origens; a unicidade é verificada a cada carga.

CREATE OR REFRESH STREAMING TABLE workspace.silver.tb_venda (
  CONSTRAINT check_venda_uuid   EXPECT (venda_uuid IS NOT NULL),
  CONSTRAINT check_usuario_uuid EXPECT (usuario_uuid IS NOT NULL),
  CONSTRAINT check_curso_uuid   EXPECT (curso_uuid IS NOT NULL),
  CONSTRAINT check_data_venda   EXPECT (data_venda IS NOT NULL),
  CONSTRAINT check_valor_pago   EXPECT (valor_pago IS NOT NULL AND valor_pago > 0)
)
COMMENT 'Vendas do site (API) e vendas corporativas das empresas parceiras (ARQUIVO).'
TBLPROPERTIES ("quality" = "silver");

CREATE FLOW silver_tb_venda_api_flow AS
INSERT INTO workspace.silver.tb_venda BY NAME
SELECT * FROM STREAM(vw_silver_tb_venda_api);

CREATE FLOW silver_tb_venda_files_flow AS
INSERT INTO workspace.silver.tb_venda BY NAME
SELECT * FROM STREAM(vw_silver_tb_venda_files);
