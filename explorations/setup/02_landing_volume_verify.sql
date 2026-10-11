-- Feature 002-landing-volume: relatório de verificação (somente leitura).
--
-- Mostra o estado atual do volume landing do schema workspace.bronze: se existe,
-- quem é o dono, como é armazenado, a descrição e quem tem acesso. Não cria, altera,
-- concede nem revoga nada, e pode ser executado em qualquer estado do ambiente.
--
-- Como executar (o profile é sempre escolhido por quem executa):
--   databricks experimental aitools tools query explorations/setup/02_landing_volume_verify.sql --profile <profile>
--
-- O ambiente está em conformidade quando o relatório não tem nenhuma linha FAIL.
-- Em um ambiente recém-configurado são 6 linhas PASS.
--
-- Para conferir o ambiente inteiro (schemas + volume) em uma única chamada:
--   databricks experimental aitools tools query \
--     explorations/setup/01_schemas_verify.sql \
--     explorations/setup/02_landing_volume_verify.sql \
--     --profile <profile> --output json | jq -r '.[].rows[] | @tsv'
--
-- ATENÇÃO: esta consulta é repetida, idêntica, no final de
-- explorations/setup/02_landing_volume.sql, que acrescenta apenas as linhas
-- 'revogado'. Mantenha as duas cópias iguais.

WITH constantes AS (
  SELECT
    'workspace'                    AS catalogo,
    'bronze'                       AS schema_nome,
    'landing'                      AS volume_nome,
    'arthur.luz@dataslight.com.br' AS dono,
    'Landing zone: arquivos de origem como chegaram, uma pasta por origem.' AS descricao_esperada,
    'workspace.bronze'             AS objeto_schema,
    'workspace.bronze.landing'     AS objeto_volume
),
esquema AS (
  SELECT
    c.objeto_schema,
    c.dono,
    s.schema_name IS NOT NULL AS existe,
    s.schema_owner            AS dono_atual
  FROM constantes AS c
  LEFT JOIN workspace.information_schema.schemata AS s
    ON s.catalog_name = c.catalogo
   AND s.schema_name = c.schema_nome
),
volume AS (
  SELECT
    c.objeto_volume,
    c.dono,
    c.descricao_esperada,
    v.volume_name IS NOT NULL AS existe,
    v.volume_owner            AS dono_atual,
    v.volume_type             AS tipo,
    v.comment                 AS descricao_atual
  FROM constantes AS c
  LEFT JOIN workspace.information_schema.volumes AS v
    ON v.volume_catalog = c.catalogo
   AND v.volume_schema = c.schema_nome
   AND v.volume_name = c.volume_nome
),
privilegios AS (
  SELECT
    p.grantee,
    p.privilege_type,
    p.inherited_from
  FROM workspace.information_schema.volume_privileges AS p
  CROSS JOIN constantes AS c
  WHERE p.volume_catalog = c.catalogo
    AND p.volume_schema = c.schema_nome
    AND p.volume_name = c.volume_nome
),
diretos_por_grantee AS (
  SELECT
    grantee,
    array_join(sort_array(collect_set(privilege_type)), ', ') AS lista_privilegios
  FROM privilegios
  WHERE inherited_from = 'NONE'
  GROUP BY grantee
),
diretos AS (
  -- Agregação sem GROUP BY: sempre devolve uma linha, mesmo sem nenhuma concessão.
  SELECT
    count_if(d.grantee = c.dono)  AS qtd_dono,
    count_if(d.grantee <> c.dono) AS qtd_outros,
    array_join(
      sort_array(collect_list(concat(d.grantee, ' [', d.lista_privilegios, ']'))),
      '; '
    ) AS lista
  FROM constantes AS c
  LEFT JOIN diretos_por_grantee AS d
    ON TRUE
),
relatorio AS (
  SELECT
    110 AS ordem,
    'alvo' AS verificacao,
    c.objeto_schema AS objeto,
    'INFO' AS resultado,
    concat(
      'usuário: ', current_user(),
      '; catálogo atual: ', current_catalog(),
      '; metastore: ', current_metastore()
    ) AS detalhe
  FROM constantes AS c

  UNION ALL

  SELECT
    120,
    'pre_requisito',
    objeto_schema,
    CASE WHEN existe AND dono_atual = dono THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT existe THEN 'schema não existe; execute antes explorations/setup/01_schemas.sql'
      WHEN dono_atual = dono THEN concat('schema existe; dono: ', dono_atual)
      ELSE concat('dono atual do schema: ', dono_atual, '; esperado: ', dono)
    END
  FROM esquema

  UNION ALL

  SELECT
    130,
    'volume_existe',
    objeto_volume,
    CASE WHEN existe THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN existe THEN 'volume existe' ELSE 'volume não existe' END
  FROM volume

  UNION ALL

  SELECT
    140,
    'dono',
    objeto_volume,
    CASE WHEN existe AND dono_atual = dono THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT existe THEN 'volume não existe'
      WHEN dono_atual = dono THEN dono_atual
      ELSE concat('dono atual: ', dono_atual, '; esperado: ', dono)
    END
  FROM volume

  UNION ALL

  SELECT
    150,
    'armazenamento',
    objeto_volume,
    CASE WHEN existe AND tipo = 'MANAGED' THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT existe THEN 'volume não existe'
      WHEN tipo = 'MANAGED' THEN tipo
      ELSE concat('tipo atual: ', tipo, '; esperado: MANAGED')
    END
  FROM volume

  UNION ALL

  SELECT
    160,
    'descricao',
    objeto_volume,
    CASE WHEN existe AND descricao_atual <=> descricao_esperada THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT existe THEN 'volume não existe'
      WHEN descricao_atual <=> descricao_esperada THEN descricao_atual
      ELSE concat(
        'descrição atual: ', coalesce(descricao_atual, '(vazia)'),
        '; esperada: ', descricao_esperada
      )
    END
  FROM volume

  UNION ALL

  SELECT
    170,
    'acesso_direto',
    v.objeto_volume,
    CASE WHEN v.existe AND d.qtd_dono = 1 AND d.qtd_outros = 0 THEN 'PASS' ELSE 'FAIL' END,
    CASE
      WHEN NOT v.existe THEN 'volume não existe'
      WHEN d.qtd_dono = 1 AND d.qtd_outros = 0 THEN d.lista
      ELSE concat(
        CASE WHEN coalesce(d.lista, '') = '' THEN 'nenhum acesso direto concedido' ELSE d.lista END,
        '; esperado: apenas ', v.dono
      )
    END
  FROM volume AS v
  CROSS JOIN diretos AS d

  UNION ALL

  SELECT
    180,
    'acesso_herdado',
    c.objeto_volume,
    CASE
      WHEN replace(upper(p.privilege_type), ' ', '_') IN ('USE_CATALOG', 'USE_SCHEMA', 'BROWSE') THEN 'INFO'
      ELSE 'FAIL'
    END,
    concat(p.grantee, ': ', p.privilege_type, ' (herdado de ', p.inherited_from, ')')
  FROM privilegios AS p
  CROSS JOIN constantes AS c
  WHERE p.inherited_from <> 'NONE'
    AND p.grantee <> c.dono
)
SELECT ordem, verificacao, objeto, resultado, detalhe
FROM relatorio
ORDER BY ordem, objeto, detalhe
