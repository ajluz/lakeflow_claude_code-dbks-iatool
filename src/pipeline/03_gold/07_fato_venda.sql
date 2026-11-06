-- Camada gold: fato de vendas (fato_venda).
-- Grão: uma venda de silver.tb_venda. Medidas valor_desconto e valor_pago, ambas aditivas.
-- Streaming table sobre STREAM(silver.tb_venda), que só recebe inserções (fluxos de append):
-- cada venda é processada uma única vez. As dimensões e tb_acesso são lidas sem STREAM
-- (joins stream-static), com o stream à esquerda.
-- As quatro dimensões usam inner join (Kimball), porque cada uma cobre todas as vendas; a
-- cobertura foi verificada por anti join = 0 antes da mudança (constituição v3.1.0,
-- Princípio V):
--   sk_tempo: dim_tempo.data = dia de data_venda; o calendário cobre 2021–2030;
--   sk_codigos: dim_codigos com os quatro códigos da venda, pelas regras de dim_codigos, que
--     contém todas as combinações; venda de ARQUIVO não tem acesso: local_acesso = 'Não se aplica';
--   sk_curso: versão do curso válida de __START_AT até o __START_AT da versão seguinte; venda
--     anterior à primeira versão usa a primeira versão; nunca só __END_AT IS NULL;
--   sk_usuario: dim_usuario.usuario_uuid; todo usuário de venda existe desde 2026-11-06.
-- O acesso continua num LEFT JOIN a partir das vendas: só são lidos acessos que terminaram em
-- compra, e as vendas de arquivo e as vendas do site sem acesso continuam no fato.
-- As chaves são resolvidas uma vez, quando a venda é processada, depois que as dimensões da
-- mesma atualização terminam de carregar. Uma linha de dimensão que chegasse numa atualização
-- posterior faria o inner join descartar a venda; a contagem de linhas conferida após cada
-- carga mostraria a perda.

CREATE OR REFRESH STREAMING TABLE workspace.gold.fato_venda
COMMENT 'Fato de vendas: uma linha por venda de silver.tb_venda, com as chaves de tempo, códigos, curso e usuário e as medidas valor_desconto e valor_pago.'
TBLPROPERTIES ("quality" = "gold")
AS
-- Uma linha por venda, lida do stream de tb_venda. O LEFT JOIN parte das vendas: só os acessos
-- que terminaram em compra são lidos, e vendas sem acesso e vendas de arquivo continuam no fato.
-- Mesmas regras de dim_codigos; venda de ARQUIVO não tem acesso: Não se aplica.
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
-- Versões dos cursos, sem os membros. Cada versão vale de __START_AT até o início da seguinte.
versoes_curso AS (
  SELECT sk_curso, curso_uuid, __START_AT,
         lead(__START_AT) OVER (PARTITION BY curso_uuid ORDER BY __START_AT) AS proximo_inicio,
         min(__START_AT) OVER (PARTITION BY curso_uuid) AS primeiro_inicio
  FROM workspace.gold.dim_curso
  WHERE sk_curso > 0
)
SELECT
  t.sk_tempo,
  c.sk_codigos,
  k.sk_curso,
  u.sk_usuario,
  s.valor_desconto,
  s.valor_pago
FROM vendas AS s
JOIN workspace.gold.dim_tempo AS t
  ON t.data = CAST(s.data_venda AS DATE)
JOIN workspace.gold.dim_codigos AS c
  ON c.origem_usuario = s.origem_usuario
 AND c.local_acesso = s.local_acesso
 AND c.forma_pagamento = s.forma_pagamento
 AND c.percentual_desconto = s.percentual_desconto
-- Versão válida na data da venda (até o início da versão seguinte; depois de uma exclusão, a
-- última versão fechada); venda anterior à primeira versão usa a primeira versão;
-- nunca só __END_AT IS NULL.
JOIN versoes_curso AS k
  ON k.curso_uuid = s.curso_uuid
 AND (
       (k.__START_AT <= s.data_venda AND (k.proximo_inicio IS NULL OR s.data_venda < k.proximo_inicio))
    OR (s.data_venda < k.primeiro_inicio AND k.__START_AT = k.primeiro_inicio)
     )
JOIN workspace.gold.dim_usuario AS u
  ON u.usuario_uuid = s.usuario_uuid;
