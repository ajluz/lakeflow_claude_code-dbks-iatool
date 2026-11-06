-- Camada silver: view do fluxo da origem API para tb_venda.
-- Lê apenas os eventos válidos de temp_tb_validacao_api que trazem pagamento
-- (fl_registro_invalido = false e payload.info_pagamento preenchido) e entrega exatamente as
-- 13 colunas de tb_venda.
-- A consulta interna define timestamp_acesso, endereco_ip_acesso, local_acesso, acesso_uuid,
-- usuario_uuid e curso_uuid com o mesmo texto de 05_tb_acesso.sql, para que cada venda
-- encontre seu acesso, seu usuário e seu curso.
-- venda_uuid inclui o nome do usuário: sem ele, eventos com o endereço 999.999.999.999 no
-- mesmo segundo repetiriam a chave.
-- Valores em DECIMAL; o desconto é convertido para DECIMAL antes de qualquer conta.
-- Sem desconto, percentual_desconto = '0%' e valor_desconto = 0.00.

CREATE TEMPORARY VIEW vw_silver_tb_venda_api
COMMENT 'Vendas vindas dos eventos válidos da API com pagamento, no formato de tb_venda.'
AS
SELECT
  md5(concat_ws('||',
      coalesce(cast(timestamp_acesso AS STRING), ''),
      coalesce(endereco_ip_acesso, ''),
      coalesce(local_acesso, ''),
      coalesce(payload.info_produto.product_name, ''),
      coalesce(payload.info_usuario.nome, '')))                              AS venda_uuid,
  timestamp_acesso                                                         AS data_venda,
  acesso_uuid,
  usuario_uuid,
  curso_uuid,
  payload.info_pagamento.forma_pagamento                                   AS forma_pagamento,
  try_cast(payload.info_pagamento.quantidade_parcelas AS INT)              AS quantidade_parcelas,
  CAST(payload.info_pagamento.valor_parcelas AS DECIMAL(9,2))              AS valor_parcelas,
  CAST(quantidade_parcelas * valor_parcelas AS DECIMAL(9,2))               AS valor_pago,
  concat(CAST(fracao * 100 AS INT), '%')                                   AS percentual_desconto,
  valor_desconto,
  'API'                                                                    AS origem,
  current_timestamp()                                                      AS data_carga
FROM (
  SELECT
    payload,
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
    try_cast(replace(regexp_replace(payload.info_produto.valor, '[^0-9,]', ''), ',', '.') AS DECIMAL(9,2)) AS preco,
    CAST(coalesce(payload.info_pagamento.disconto, 0) AS DECIMAL(5,2))                                       AS fracao,
    CAST(preco * fracao AS DECIMAL(9,2))                                                                     AS valor_desconto
  FROM STREAM(presentation.silver.temp_tb_validacao_api)
  WHERE NOT fl_registro_invalido
    AND payload.info_pagamento IS NOT NULL
);
