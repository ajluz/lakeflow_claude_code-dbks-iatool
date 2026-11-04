-- Camada gold: dimensão de usuários (dim_usuario).
-- Grão: um usuário. SCD tipo 1: o fluxo AUTO CDC mantém os valores mais recentes de
-- silver.tb_usuario, sem histórico. Silver não entrega exclusões, então não há condição de
-- exclusão: um usuário removido de silver mantém a sua linha.
-- sk_usuario vem de vw_gold_dim_usuario_tb_usuario e nunca muda para o mesmo usuário.
-- Membros padrão: -1 'Desconhecido' e -2 'Não se aplica', com chaves fixas, os únicos
-- valores negativos. Os fatos resolvem sk_usuario pela junção em usuario_uuid e usam -1
-- quando não há correspondência; -2 quando o fato não tem usuário por natureza.
-- data_carga é o horário em que gold gravou a linha, não o de silver: não muda em uma
-- atualização sem dados novos.

CREATE OR REFRESH STREAMING TABLE workspace.gold.dim_usuario (
  sk_usuario        BIGINT,
  usuario_uuid      STRING,
  nome_usuario      STRING,
  email_usuario     STRING,
  idade_usuario     INT,
  sexo_usuario      STRING,
  estado_usuario    STRING,
  profissao_usuario STRING,
  empresa_usuario   STRING,
  origem            STRING,
  data_carga        TIMESTAMP
)
COMMENT 'Dimensão de usuários: um registro por usuário de silver.tb_usuario (SCD tipo 1), com chave substituta estável e os membros Desconhecido (-1) e Não se aplica (-2).'
TBLPROPERTIES ("quality" = "gold");

CREATE FLOW gold_dim_usuario_tb_usuario_flow AS AUTO CDC INTO workspace.gold.dim_usuario
FROM STREAM(vw_gold_dim_usuario_tb_usuario)
KEYS (usuario_uuid)
SEQUENCE BY data_carga_silver
COLUMNS * EXCEPT (data_carga_silver)
STORED AS SCD TYPE 1;
