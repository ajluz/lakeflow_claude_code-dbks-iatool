-- Feature 001-medallion-schemas: cria os schemas bronze, silver e gold no catálogo
-- presentation e aplica a regra de acesso: arthur.luz@dataslight.com.br é o dono e a
-- única identidade com acesso concedido nos três schemas.
--
-- O script pode ser executado quantas vezes for preciso. Ele nunca remove um schema
-- nem um objeto dentro de um schema, não toca em nenhum outro schema e não altera
-- concessões feitas no catálogo.
--
-- Como executar (o profile é sempre escolhido por quem executa):
--   databricks experimental aitools tools query explorations/setup/01_schemas.sql --profile <profile>
--
-- Antes de qualquer alteração o script confere três pré-condições e para com erro,
-- sem mudar nada, se alguma falhar:
--   P1. o catálogo presentation existe;
--   P2. quem executa é arthur.luz@dataslight.com.br;
--   P3. nenhum dos três schemas existe com outro dono.
--
-- O resultado é o relatório de verificação, o mesmo de explorations/setup/01_schemas_verify.sql,
-- acrescido das linhas 'revogado'.

BEGIN
  DECLARE v_catalogo STRING DEFAULT 'presentation';
  DECLARE v_dono STRING DEFAULT 'arthur.luz@dataslight.com.br';
  DECLARE v_qtd INT DEFAULT 0;
  DECLARE v_msg STRING DEFAULT '';
  DECLARE v_descricao_atual STRING;
  DECLARE v_revogados ARRAY<STRUCT<objeto STRING, detalhe STRING>>
    DEFAULT CAST(array() AS ARRAY<STRUCT<objeto STRING, detalhe STRING>>);

  -- P1: o catálogo precisa existir. Este script nunca cria um catálogo.
  SET v_qtd = (
    SELECT count(*)
    FROM system.information_schema.catalogs
    WHERE catalog_name = v_catalogo
  );
  IF v_qtd = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'catalog presentation not found';
  END IF;

  -- P2: somente o dono executa o setup, para que os schemas nunca fiquem
  -- pertencendo a quem o executou.
  IF current_user() <> v_dono THEN
    SET v_msg = concat(
      'must be run as arthur.luz@dataslight.com.br, but the current user is ',
      current_user()
    );
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = v_msg;
  END IF;

  -- P3: um schema que já existe com outro dono bloqueia a execução inteira.
  -- Os três são conferidos antes do primeiro CREATE.
  SET v_msg = (
    SELECT array_join(
      collect_list(concat('schema ', schema_name, ' is owned by ', schema_owner)),
      '; '
    )
    FROM presentation.information_schema.schemata
    WHERE catalog_name = v_catalogo
      AND schema_name IN ('bronze', 'silver', 'gold')
      AND schema_owner <> v_dono
  );
  IF coalesce(v_msg, '') <> '' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = v_msg;
  END IF;

  camadas: FOR camada AS
    SELECT nome, descricao
    FROM VALUES
      (1, 'bronze', 'Camada bronze: dados brutos, exatamente como chegaram da origem.'),
      (2, 'silver', 'Camada silver: dados validados, tipados e conformados.'),
      (3, 'gold',   'Camada gold: modelo analítico (dimensões, fatos e tabelas desnormalizadas).')
      AS t (pos, nome, descricao)
    ORDER BY pos
  DO
    EXECUTE IMMEDIATE concat('CREATE SCHEMA IF NOT EXISTS presentation.', camada.nome);

    -- A descrição só é reaplicada quando está diferente da esperada.
    SET v_descricao_atual = (
      SELECT comment
      FROM presentation.information_schema.schemata
      WHERE catalog_name = v_catalogo
        AND schema_name = camada.nome
    );
    IF NOT (v_descricao_atual <=> camada.descricao) THEN
      EXECUTE IMMEDIATE concat(
        'COMMENT ON SCHEMA presentation.', camada.nome, " IS '", camada.descricao, "'"
      );
    END IF;

    EXECUTE IMMEDIATE concat(
      'GRANT ALL PRIVILEGES ON SCHEMA presentation.', camada.nome, ' TO `', v_dono, '`'
    );

    -- Revoga todo privilégio concedido diretamente no schema a qualquer outra
    -- identidade. Privilégios herdados do catálogo não são alterados.
    concessoes: FOR concessao AS
      SELECT DISTINCT grantee, privilege_type
      FROM presentation.information_schema.schema_privileges
      WHERE catalog_name = v_catalogo
        AND schema_name = camada.nome
        AND inherited_from = 'NONE'
        AND grantee <> v_dono
    DO
      EXECUTE IMMEDIATE concat(
        'REVOKE ', replace(concessao.privilege_type, '_', ' '),
        ' ON SCHEMA presentation.', camada.nome,
        ' FROM `', concessao.grantee, '`'
      );
      SET v_revogados = array_append(
        v_revogados,
        named_struct(
          'objeto', concat(v_catalogo, '.', camada.nome),
          'detalhe', concat(concessao.grantee, ': ', concessao.privilege_type)
        )
      );
    END FOR concessoes;
  END FOR camadas;

  -- Relatório de verificação. Cópia idêntica de explorations/setup/01_schemas_verify.sql,
  -- acrescida apenas das linhas 'revogado'. Mantenha as duas cópias iguais.
  -- O information_schema já reflete os REVOKE feitos acima nesta mesma execução
  -- (verificado em 2026-10-10), então 'acesso_direto' mostra o estado final.
  WITH constantes AS (
    SELECT
      'presentation'                    AS catalogo,
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
    LEFT JOIN presentation.information_schema.schemata AS s
      ON s.catalog_name = c.catalogo
     AND s.schema_name = e.nome
  ),
  privilegios AS (
    SELECT
      p.schema_name AS nome,
      p.grantee,
      p.privilege_type,
      p.inherited_from
    FROM presentation.information_schema.schema_privileges AS p
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
    FROM presentation.information_schema.catalog_privileges AS cp
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
    FROM presentation.information_schema.catalogs AS k
    CROSS JOIN constantes AS c
    WHERE k.catalog_name = c.catalogo

    UNION ALL

    -- Somente no script de setup: privilégios revogados nesta execução.
    SELECT
      80,
      'revogado',
      r.objeto,
      'INFO',
      r.detalhe
    FROM (SELECT explode(v_revogados) AS r)
  )
  SELECT ordem, verificacao, objeto, resultado, detalhe
  FROM relatorio
  ORDER BY ordem, objeto, detalhe;
END
