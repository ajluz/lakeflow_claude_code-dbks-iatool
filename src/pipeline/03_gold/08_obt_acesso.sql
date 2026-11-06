-- Camada gold: one-big-table de acessos do site (obt_acesso).
-- Grão: uma linha por local_acesso, endereco_ip_acesso e data do acesso; as quantidades são
-- somadas sobre os acessos de cada combinação.
-- Fontes: silver.tb_acesso (acessos), silver.tb_venda (vendas do site, por acesso_uuid) e
-- gold.dim_tempo (calendário). fato_venda não é usado: não guarda o acesso.
-- Joins à esquerda a partir dos acessos: nenhum acesso se perde na busca de vendas ou do
-- calendário.
-- As medidas continuam definidas nos seus próprios datasets; esta tabela apenas as conta.
-- qtde_usuario conta os acessos com usuário identificado.
-- qtde_vendidos conta as vendas do site ligadas aos acessos; vendas de arquivo e vendas sem
-- acesso em tb_acesso não entram.

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.obt_acesso
COMMENT 'One-big-table de acessos do site por local, endereço e dia, com o calendário e as quantidades de acessos, usuários e vendas.'
TBLPROPERTIES ("quality" = "gold")
AS
-- As vendas são contadas por acesso antes do join, para que um acesso com mais de uma venda
-- não se repita.
WITH vendas_por_acesso AS (
  SELECT acesso_uuid, count(*) AS qtde_vendas
  FROM workspace.silver.tb_venda
  WHERE origem = 'API' AND acesso_uuid IS NOT NULL
  GROUP BY acesso_uuid
),
-- Acessos agrupados por local, endereço e dia.
acessos AS (
  SELECT
    a.local_acesso,
    a.endereco_ip_acesso,
    CAST(a.timestamp_acesso AS DATE) AS data,
    count(*) AS qtde_acesso,
    count_if(a.usuario_uuid IS NOT NULL) AS qtde_usuario,
    coalesce(sum(v.qtde_vendas), 0) AS qtde_vendidos
  FROM workspace.silver.tb_acesso AS a
  LEFT JOIN vendas_por_acesso AS v
    ON v.acesso_uuid = a.acesso_uuid
  GROUP BY a.local_acesso, a.endereco_ip_acesso, CAST(a.timestamp_acesso AS DATE)
)
SELECT
  s.local_acesso,
  s.endereco_ip_acesso,
  s.data,
  t.ano,
  t.mes,
  t.mes_ano,
  t.dia_mes,
  t.dia_semana,
  t.dia_semana_int,
  t.fl_dia_semana,
  t.dia_ano,
  t.fl_ultimo_dia_mes,
  t.semana_ano,
  t.semestre,
  t.trimestre,
  t.bimestre,
  s.qtde_acesso,
  s.qtde_usuario,
  s.qtde_vendidos
FROM acessos AS s
LEFT JOIN workspace.gold.dim_tempo AS t
  ON t.data = s.data;
