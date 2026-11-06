-- Camada gold: fato de vendas (fato_venda).
-- Grão: uma venda de silver.tb_venda. Medidas valor_desconto e valor_pago, ambas aditivas.
-- Streaming table sobre STREAM(silver.tb_venda), que só recebe inserções (fluxos de append):
-- cada venda é processada uma única vez. As dimensões e tb_acesso são lidas sem STREAM
-- (joins stream-static), com o stream à esquerda.
-- Cada chave vem de um LEFT JOIN e usa -1 (Desconhecido) quando não há correspondência. Não há
-- inner join: nenhuma venda pode se perder (Princípios I, V e VII).
--   sk_tempo: dim_tempo.data = dia de data_venda;
--   sk_codigos: dim_codigos com os quatro códigos da venda, pelas regras de dim_codigos;
--     venda de ARQUIVO não tem acesso: local_acesso = 'Não se aplica';
--   sk_curso: versão do curso em vigor em data_venda; venda anterior à primeira versão usa a
--     primeira versão; nunca só __END_AT IS NULL;
--   sk_usuario: dim_usuario.usuario_uuid.
-- As chaves são resolvidas uma vez, quando a venda é processada, depois que as dimensões da
-- mesma atualização terminam de carregar. Uma linha de dimensão que chegue depois não muda
-- vendas já gravadas.

CREATE OR REFRESH STREAMING TABLE workspace.gold.fato_venda
COMMENT 'Fato de vendas: uma linha por venda de silver.tb_venda, com as chaves de tempo, códigos, curso e usuário e as medidas valor_desconto e valor_pago.'
TBLPROPERTIES ("quality" = "gold")
AS
-- Uma linha por venda, lida do stream de tb_venda. LEFT JOIN: vendas sem acesso e vendas de
-- arquivo continuam no fato. Mesmas regras de dim_codigos; venda de ARQUIVO não tem acesso:
-- Não se aplica.
WITH vendas AS (
  SELECT
    v.data_venda,
    v.usuario_uuid,
    v.curso_uuid,
    v.valor_desconto,
    v.valor_pago,
    v.origem AS origem_usuario,
    CASE WHEN v.origem = 'ARQUIVO' THEN 'Não se aplica'
         ELSE coalesce(a.local_acesso, 'Desconhecido') END AS local_acesso,
    coalesce(v.forma_pagamento, 'Desconhecido') AS forma_pagamento,
    coalesce(v.percentual_desconto, 'Não se aplica') AS percentual_desconto
  FROM STREAM(workspace.silver.tb_venda) AS v
  LEFT JOIN workspace.silver.tb_acesso AS a
    ON v.origem = 'API' AND a.acesso_uuid = v.acesso_uuid
),
-- Versões dos cursos, sem os membros.
versoes_curso AS (
  SELECT sk_curso, curso_uuid, __START_AT, __END_AT,
         min(__START_AT) OVER (PARTITION BY curso_uuid) AS primeiro_inicio
  FROM workspace.gold.dim_curso
  WHERE sk_curso > 0
)
SELECT
  coalesce(t.sk_tempo, -1)   AS sk_tempo,
  coalesce(c.sk_codigos, -1) AS sk_codigos,
  coalesce(k.sk_curso, -1)   AS sk_curso,
  coalesce(u.sk_usuario, -1) AS sk_usuario,
  s.valor_desconto,
  s.valor_pago
FROM vendas AS s
LEFT JOIN workspace.gold.dim_tempo AS t
  ON t.data = CAST(s.data_venda AS DATE)
LEFT JOIN workspace.gold.dim_codigos AS c
  ON c.origem_usuario = s.origem_usuario
 AND c.local_acesso = s.local_acesso
 AND c.forma_pagamento = s.forma_pagamento
 AND c.percentual_desconto = s.percentual_desconto
-- Versão em vigor na data da venda; venda anterior à primeira versão usa a primeira versão;
-- nunca só __END_AT IS NULL.
LEFT JOIN versoes_curso AS k
  ON k.curso_uuid = s.curso_uuid
 AND (
       (s.data_venda >= k.__START_AT AND (k.__END_AT IS NULL OR s.data_venda < k.__END_AT))
    OR (s.data_venda < k.primeiro_inicio AND k.__START_AT = k.primeiro_inicio)
     )
LEFT JOIN workspace.gold.dim_usuario AS u
  ON u.usuario_uuid = s.usuario_uuid;
