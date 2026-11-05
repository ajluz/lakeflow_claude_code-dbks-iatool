-- Camada gold: dimensão de usuários (dim_usuario). Grão: um usuário. SCD tipo 1.
-- Os fatos resolvem sk_usuario pela junção em usuario_uuid e usam -1 quando não há
-- correspondência; -2 quando o fato não tem usuário por natureza.

CREATE OR REFRESH STREAMING TABLE workspace.gold.dim_usuario
COMMENT 'Dimensão de usuários: um registro por usuário de silver.tb_usuario (SCD tipo 1), com chave substituta estável e os membros Desconhecido (-1) e Não se aplica (-2).'
TBLPROPERTIES ("quality" = "gold");

-- Usuários. Silver não entrega exclusões, então não há condição de exclusão.
CREATE FLOW gold_dim_usuario_tb_usuario_flow AS AUTO CDC INTO workspace.gold.dim_usuario
FROM STREAM(vw_gold_dim_usuario_tb_usuario)
KEYS (usuario_uuid)
SEQUENCE BY data_carga_silver
COLUMNS * EXCEPT (data_carga_silver)
STORED AS SCD TYPE 1;

-- Membros padrão, carregados uma única vez. Um snapshot trata as chaves ausentes como
-- excluídas na sua versão: a versão de 1900 é mais antiga que qualquer linha de silver, então
-- os usuários não são excluídos. Não remova WITH VERSION.
CREATE FLOW gold_dim_usuario_membros_flow AS AUTO CDC ONCE INTO workspace.gold.dim_usuario
FROM SNAPSHOT (
  SELECT CAST(-1 AS BIGINT) AS sk_usuario, '-1' AS usuario_uuid,
         'Desconhecido' AS nome_usuario, 'Desconhecido' AS email_usuario,
         CAST(NULL AS INT) AS idade_usuario, 'Desconhecido' AS sexo_usuario,
         'Desconhecido' AS estado_usuario, 'Desconhecido' AS profissao_usuario,
         'Desconhecido' AS empresa_usuario, 'Desconhecido' AS origem,
         current_timestamp() AS data_carga
  UNION ALL
  SELECT CAST(-2 AS BIGINT), '-2', 'Não se aplica', 'Não se aplica', CAST(NULL AS INT),
         'Não se aplica', 'Não se aplica', 'Não se aplica', 'Não se aplica',
         'Não se aplica', current_timestamp()
)
WITH VERSION (
  SELECT TIMESTAMP'1900-01-01' AS versao
  WHERE NOT EXISTS (SELECT 1 FROM last_snapshot_version())
)
KEYS (usuario_uuid)
STORED AS SCD TYPE 1;
