-- Camada silver: view do fluxo da origem ARQUIVO para tb_venda.
-- Lê as vendas corporativas de vw_bronze_dados_files e entrega exatamente as 13 colunas de
-- tb_venda.
-- Uma venda corporativa não tem acesso ao site (acesso_uuid vazio) e é um único pagamento
-- pix (quantidade_parcelas = 1).
-- usuario_uuid usa o mesmo texto de 07_vw_silver_tb_usuario_files.sql; curso_uuid = md5 do
-- nome do curso, igual ao identificador do catálogo.
-- O preço de tabela ('R$ 247,00') e o desconto ('5%') chegam como texto e viram DECIMAL na
-- consulta interna; valor_parcelas = preço - valor_desconto.

CREATE TEMPORARY VIEW vw_silver_tb_venda_files
COMMENT 'Vendas corporativas vindas dos arquivos das empresas parceiras, no formato de tb_venda.'
AS
SELECT
  md5(concat_ws('||',
      coalesce(nome_empresa, ''),
      coalesce(nome_funcionario, ''),
      coalesce(cast(data_venda AS STRING), ''),
      coalesce(curso, '')))                                                AS venda_uuid,
  CAST(data_venda AS TIMESTAMP)                                            AS data_venda,
  CAST(NULL AS STRING)                                                     AS acesso_uuid,
  md5(concat_ws('||', coalesce(nome_empresa, ''), coalesce(nome_funcionario, ''))) AS usuario_uuid,
  md5(curso)                                                               AS curso_uuid,
  'pix'                                                                    AS forma_pagamento,
  1                                                                        AS quantidade_parcelas,
  CAST(preco - valor_desconto AS DECIMAL(9,2))                             AS valor_parcelas,
  CAST(quantidade_parcelas * valor_parcelas AS DECIMAL(9,2))               AS valor_pago,
  coalesce(disconto, '0%')                                                 AS percentual_desconto,
  valor_desconto,
  'ARQUIVO'                                                                AS origem,
  current_timestamp()                                                      AS data_carga
FROM (
  SELECT
    nome_empresa,
    nome_funcionario,
    data_venda,
    curso,
    disconto,
    try_cast(replace(regexp_replace(valor, '[^0-9,]', ''), ',', '.') AS DECIMAL(9,2))                    AS preco,
    CAST(CAST(replace(coalesce(disconto, '0%'), '%', '') AS DECIMAL(5,2)) / 100 AS DECIMAL(5,2))         AS fracao,
    CAST(preco * fracao AS DECIMAL(9,2))                                                                 AS valor_desconto
  FROM STREAM(vw_bronze_dados_files)
);
