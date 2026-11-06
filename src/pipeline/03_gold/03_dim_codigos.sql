-- Camada gold: dimensão junk de códigos da venda (dim_codigos). SCD tipo 1.
-- Grão: cada combinação possível de origem_usuario, local_acesso, forma_pagamento e
-- percentual_desconto.
-- Construída a partir de quatro listas de valores, cruzadas entre si:
--   origem, forma de pagamento e desconto: valores distintos de silver.tb_venda;
--   local de acesso: valores distintos de silver.tb_acesso, mais 'Desconhecido'.
-- As listas são cruzadas, nunca as tabelas: cruzar as tabelas multiplicaria as vendas pelos
-- acessos antes do DISTINCT.
-- Regras: origem ARQUIVO -> local_acesso 'Não se aplica'; forma de pagamento vazia ->
-- 'Desconhecido'; desconto vazio -> 'Não se aplica'.
-- Chave: xxhash64 dos quatro códigos com o bit de sinal zerado. É determinística, então
-- nunca é reatribuída, nem quando a view é recalculada; não é identity, que materialized
-- views não suportam. Os membros são -1 (Desconhecido) e -2 (Não se aplica).
-- Os fatos resolvem sk_codigos calculando os mesmos quatro códigos e comparando os quatro;
-- sem correspondência, usam -1.

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_codigos
COMMENT 'Dimensão junk: uma linha por combinação possível de origem, local de acesso, forma de pagamento e percentual de desconto, com chave substituta estável e os membros -1 e -2.'
TBLPROPERTIES ("quality" = "gold")
AS
WITH origens AS (
  SELECT DISTINCT origem AS origem_usuario
  FROM workspace.silver.tb_venda
),
-- Desconhecido: venda do site sem acesso em tb_acesso.
locais AS (
  SELECT DISTINCT local_acesso
  FROM workspace.silver.tb_acesso
  UNION
  SELECT 'Desconhecido'
),
formas AS (
  SELECT DISTINCT coalesce(forma_pagamento, 'Desconhecido') AS forma_pagamento
  FROM workspace.silver.tb_venda
),
descontos AS (
  SELECT DISTINCT coalesce(percentual_desconto, 'Não se aplica') AS percentual_desconto
  FROM workspace.silver.tb_venda
),
-- Cruza as listas de valores, não as tabelas.
combinacoes AS (
  SELECT DISTINCT
    o.origem_usuario,
    CASE WHEN o.origem_usuario = 'ARQUIVO' THEN 'Não se aplica' ELSE l.local_acesso END AS local_acesso,
    f.forma_pagamento,
    d.percentual_desconto
  FROM origens AS o
  CROSS JOIN locais AS l
  CROSS JOIN formas AS f
  CROSS JOIN descontos AS d
)
SELECT
  -- Determinística: a mesma combinação tem sempre a mesma chave.
  xxhash64(origem_usuario, local_acesso, forma_pagamento, percentual_desconto)
    & 9223372036854775807 AS sk_codigos,
  origem_usuario,
  local_acesso,
  forma_pagamento,
  percentual_desconto,
  current_timestamp() AS data_carga
FROM combinacoes

-- Membros, para fatos cujos códigos faltam ou não se aplicam. Um membro nunca coincide com
-- uma combinação, porque a origem_usuario de uma combinação é sempre API ou ARQUIVO.
UNION ALL
SELECT CAST(-1 AS BIGINT), 'Desconhecido', 'Desconhecido', 'Desconhecido', 'Desconhecido',
       current_timestamp()
UNION ALL
SELECT CAST(-2 AS BIGINT), 'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica',
       current_timestamp();
