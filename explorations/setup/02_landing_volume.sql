-- Feature 002-landing-volume: cria o volume gerenciado landing no schema
-- workspace.bronze e aplica a regra de acesso: arthur.luz@dataslight.com.br é o dono
-- e a única identidade com acesso concedido no volume.
--
-- O script pode ser executado quantas vezes for preciso. Ele nunca remove nem
-- substitui o volume, não toca nos arquivos que estão dentro dele, não altera
-- nenhum schema, tabela ou outro volume, e não muda concessões feitas no schema
-- ou no catálogo.
--
-- Como executar (o profile é sempre escolhido por quem executa):
--   databricks experimental aitools tools query explorations/setup/02_landing_volume.sql --profile <profile>
--
-- Antes de qualquer alteração o script confere cinco pré-condições e para com erro,
-- sem mudar nada, se alguma falhar:
--   P1. o schema workspace.bronze existe (passo 01_schemas.sql já executado);
--   P2. quem executa é arthur.luz@dataslight.com.br;
--   P3. o schema workspace.bronze pertence a arthur.luz@dataslight.com.br;
--   P4. não existe tabela nem view chamada landing em workspace.bronze;
--   P5. se o volume landing já existe, ele pertence a arthur.luz@dataslight.com.br.
--
-- O resultado é o relatório de verificação, o mesmo de
-- explorations/setup/02_landing_volume_verify.sql, acrescido das linhas 'revogado'.

BEGIN
  DECLARE v_catalogo STRING DEFAULT 'workspace';
  DECLARE v_schema STRING DEFAULT 'bronze';
  DECLARE v_volume STRING DEFAULT 'landing';
  DECLARE v_dono STRING DEFAULT 'arthur.luz@dataslight.com.br';
  DECLARE v_descricao STRING
    DEFAULT 'Landing zone: arquivos de origem como chegaram, uma pasta por origem.';
  DECLARE v_qtd INT DEFAULT 0;
  DECLARE v_msg STRING DEFAULT '';
  DECLARE v_descricao_atual STRING;
  DECLARE v_revogados ARRAY<STRUCT<objeto STRING, detalhe STRING>>
    DEFAULT CAST(array() AS ARRAY<STRUCT<objeto STRING, detalhe STRING>>);

  -- P1: o schema precisa existir. Este script nunca cria o schema: isso é papel
  -- do passo 01, que também aplica a regra de acesso do schema.
  SET v_qtd = (
    SELECT count(*)
    FROM workspace.information_schema.schemata
    WHERE catalog_name = v_catalogo
      AND schema_name = v_schema
  );
  IF v_qtd = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'schema workspace.bronze not found; run explorations/setup/01_schemas.sql first';
  END IF;

  -- P2: somente o dono executa o setup, para que o volume nunca fique pertencendo
  -- a quem o executou.
  IF current_user() <> v_dono THEN
    SET v_msg = concat(
      'must be run as arthur.luz@dataslight.com.br, but the current user is ',
      current_user()
    );
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = v_msg;
  END IF;

  -- P3: o schema precisa pertencer ao dono; do contrário a regra de acesso do
  -- passo 01 não vale e o volume herdaria um acesso que não é o esperado.
  SET v_msg = (
    SELECT max(concat('schema bronze is owned by ', schema_owner))
    FROM workspace.information_schema.schemata
    WHERE catalog_name = v_catalogo
      AND schema_name = v_schema
      AND schema_owner <> v_dono
  );
  IF v_msg IS NOT NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = v_msg;
  END IF;

  -- P4: uma tabela ou view com o mesmo nome impede a criação do volume.
  SET v_msg = (
    SELECT max(concat(
      'an object named landing already exists in workspace.bronze (', table_type, ')'
    ))
    FROM workspace.information_schema.tables
    WHERE table_catalog = v_catalogo
      AND table_schema = v_schema
      AND table_name = v_volume
  );
  IF v_msg IS NOT NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = v_msg;
  END IF;

  -- P5: um volume landing que já existe com outro dono bloqueia a execução.
  SET v_msg = (
    SELECT max(concat('volume landing is owned by ', volume_owner))
    FROM workspace.information_schema.volumes
    WHERE volume_catalog = v_catalogo
      AND volume_schema = v_schema
      AND volume_name = v_volume
      AND volume_owner <> v_dono
  );
  IF v_msg IS NOT NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = v_msg;
  END IF;

  -- Volume gerenciado: sem LOCATION. IF NOT EXISTS garante que um volume que já
  -- existe, com seus arquivos, nunca é substituído.
  EXECUTE IMMEDIATE 'CREATE VOLUME IF NOT EXISTS workspace.bronze.landing';

  -- A descrição só é reaplicada quando está diferente da esperada.
  SET v_descricao_atual = (
    SELECT max(comment)
    FROM workspace.information_schema.volumes
    WHERE volume_catalog = v_catalogo
      AND volume_schema = v_schema
      AND volume_name = v_volume
  );
  IF NOT (v_descricao_atual <=> v_descricao) THEN
    EXECUTE IMMEDIATE concat(
      "COMMENT ON VOLUME workspace.bronze.landing IS '", v_descricao, "'"
    );
  END IF;

  EXECUTE IMMEDIATE concat(
    'GRANT ALL PRIVILEGES ON VOLUME workspace.bronze.landing TO `', v_dono, '`'
  );

  -- Revoga todo privilégio concedido diretamente no volume a qualquer outra
  -- identidade. Privilégios herdados do schema ou do catálogo não são alterados.
  concessoes: FOR concessao AS
    SELECT DISTINCT grantee, privilege_type
    FROM workspace.information_schema.volume_privileges
    WHERE volume_catalog = v_catalogo
      AND volume_schema = v_schema
      AND volume_name = v_volume
      AND inherited_from = 'NONE'
      AND grantee <> v_dono
  DO
    EXECUTE IMMEDIATE concat(
      'REVOKE ', replace(concessao.privilege_type, '_', ' '),
      ' ON VOLUME workspace.bronze.landing FROM `', concessao.grantee, '`'
    );
    SET v_revogados = array_append(
      v_revogados,
      named_struct(
        'objeto', 'workspace.bronze.landing',
        'detalhe', concat(concessao.grantee, ': ', concessao.privilege_type)
      )
    );
  END FOR concessoes;

  -- Relatório de verificação. Cópia idêntica de
  -- explorations/setup/02_landing_volume_verify.sql, acrescida apenas das linhas
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

    UNION ALL

    -- Somente no script de setup: privilégios revogados nesta execução.
    SELECT
      190,
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
