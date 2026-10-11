-- Feature 001-medallion-schemas: relatório de verificação (somente leitura).
--
-- Mostra o estado atual dos schemas bronze, silver e gold do catálogo workspace:
-- se existem, quem é o dono, a descrição e quem tem acesso. Não cria, altera,
-- concede nem revoga nada, e pode ser executado em qualquer estado do ambiente.
--
-- Como executar (o profile é sempre escolhido por quem executa):
--   databricks experimental aitools tools query setup/01_schemas_verify.sql --profile <profile>
--
-- O ambiente está em conformidade quando o relatório não tem nenhuma linha FAIL.
-- Em um ambiente recém-configurado são 12 linhas PASS (4 verificações x 3 schemas).
--
-- ATENÇÃO: esta consulta é repetida, idêntica, no final de setup/01_schemas.sql,
-- que acrescenta apenas as linhas 'revogado'. Mantenha as duas cópias iguais.

WITH constantes AS (
  SELECT
    'workspace'                    AS catalogo,
    'arthur.luz@dataslight.com.br' AS dono
),
esperado AS (
  SELECT *
  FROM VALUES
    (1, 'bronze', 'Camada bronze: dados brutos, exatamente como chegaram da origem.'),
    (2, 'silver', 'Camada silver: dados validados, tipados e conformados.'),
    (3, 'gold',   'Camada gold: modelo analítico (dimensões, fatos e tabelas desnormalizadas).')
    AS t (pos, nome, descricao)
),
schemas AS (
  SELECT
    e.pos,
    e.nome,
    concat(c.catalogo, '.', e.nome) AS objeto,
    e.descricao                     AS descricao_esperada,
    s.schema_name IS NOT NULL       AS existe,
    s.schema_owner                  AS dono_atual,
    s.comment                       AS descricao_atual,
    c.dono
  FROM esperado AS e
  CROSS JOIN constantes AS c
  LEFT JOIN workspace.information_schema.schemata AS s
    ON s.catalog_name = c.catalogo
   AND s.schema_name = e.nome
),
privilegios AS (
  SELECT
    p.schema_name AS nome,
    p.grantee,
    p.privilege_type,
    p.inherited_from
  FROM workspace.information_schema.schema_privileges AS p
  CROSS JOIN constantes AS c
  WHERE p.catalog_name = c.catalogo
    AND p.schema_name IN (SELECT nome FROM esperado)
),
diretos_por_grantee AS (
  SELECT
    nome,
    grantee,
    array_join(sort_array(collect_set(privilege_type)), ', ') AS lista_privilegios
  FROM privilegios
  WHERE inherited_from = 'NONE'
  GROUP BY nome, grantee
),
diretos AS (
  SELECT
    d.nome,
    count_if(d.grantee = c.dono)  AS qtd_dono,
    count_if(d.grantee <> c.dono) AS qtd_outros,
    array_join(
      sort_array(collect_list(concat(d.grantee, ' [', d.lista_privilegios, ']'))),
      '; '
    ) AS lista
  FROM diretos_por_grantee AS d
  CROSS JOIN constantes AS c
  GROUP BY d.nome
),
relatorio AS (
  SELECT
    10 AS ordem,
    'alvo' AS verificacao,
    c.catalogo AS objeto,
    'INFO' AS resultado,
    concat(
      'usuário: ', current_user(),
      '; catálogo atual: ', current_catalog(),
      '; metastore: ', current_metastore()
    ) AS detalhe
  FROM constantes AS c

  UNION ALL

  SELECT
    20 + pos,
    'schema_existe',
    objeto,
    CASE WHEN existe THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN existe THEN 'schema existe' ELSE 'schema não existe' END
  FROM schemas

  UNION ALL

  SELECT
    30 + pos,
    'dono',
    objeto,
    CASE WHEN existe AND dono_atual = dono THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT existe THEN 'schema não existe'
      WHEN dono_atual = dono THEN dono_atual
      ELSE concat('dono atual: ', dono_atual, '; esperado: ', dono)
    END
  FROM schemas

  UNION ALL

  SELECT
    40 + pos,
    'descricao',
    objeto,
    CASE WHEN existe AND descricao_atual <=> descricao_esperada THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT existe THEN 'schema não existe'
      WHEN descricao_atual <=> descricao_esperada THEN descricao_atual
      ELSE concat(
        'descrição atual: ', coalesce(descricao_atual, '(vazia)'),
        '; esperada: ', descricao_esperada
      )
    END
  FROM schemas

  UNION ALL

  SELECT
    50 + s.pos,
    'acesso_direto',
    s.objeto,
    CASE
      WHEN s.existe AND coalesce(d.qtd_dono, 0) = 1 AND coalesce(d.qtd_outros, 0) = 0 THEN 'PASS'
      ELSE 'FAIL'
    END,
    CASE
      WHEN NOT s.existe THEN 'schema não existe'
      WHEN coalesce(d.qtd_dono, 0) = 1 AND coalesce(d.qtd_outros, 0) = 0 THEN d.lista
      ELSE concat(
        coalesce(d.lista, 'nenhum acesso direto concedido'),
        '; esperado: apenas ', s.dono
      )
    END
  FROM schemas AS s
  LEFT JOIN diretos AS d
    ON d.nome = s.nome

  UNION ALL

  SELECT
    60,
    'acesso_herdado',
    concat(c.catalogo, '.', p.nome),
    CASE
      WHEN replace(upper(p.privilege_type), ' ', '_') IN ('USE_CATALOG', 'BROWSE') THEN 'INFO'
      ELSE 'FAIL'
    END,
    concat(p.grantee, ': ', p.privilege_type, ' (herdado de ', p.inherited_from, ')')
  FROM privilegios AS p
  CROSS JOIN constantes AS c
  WHERE p.inherited_from <> 'NONE'
    AND p.grantee <> c.dono

  UNION ALL

  SELECT
    60,
    'acesso_herdado',
    c.catalogo,
    CASE
      WHEN replace(upper(cp.privilege_type), ' ', '_') IN ('USE_CATALOG', 'BROWSE') THEN 'INFO'
      ELSE 'FAIL'
    END,
    concat(cp.grantee, ': ', cp.privilege_type, ' (concedido no catálogo)')
  FROM workspace.information_schema.catalog_privileges AS cp
  CROSS JOIN constantes AS c
  WHERE cp.catalog_name = c.catalogo
    AND cp.grantee <> c.dono

  UNION ALL

  SELECT
    70,
    'dono_catalogo',
    c.catalogo,
    'INFO',
    concat(
      'dono do catálogo: ', k.catalog_owner,
      '; membros deste dono podem gerenciar os schemas por desenho da plataforma'
    )
  FROM workspace.information_schema.catalogs AS k
  CROSS JOIN constantes AS c
  WHERE k.catalog_name = c.catalogo
)
SELECT ordem, verificacao, objeto, resultado, detalhe
FROM relatorio
ORDER BY ordem, objeto, detalhe
